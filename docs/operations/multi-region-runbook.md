# Multi-Region Runbook (P3.6)

How chrono-synth runs active-active across two AWS regions, and how to
recover when one of them goes away.

## Topology

```
                    ┌──────────────────────┐
                    │ Route53 weighted A   │
                    │  api.chrono.example  │
                    │  70% → us-west       │
                    │  30% → eu-west       │
                    └──────────┬───────────┘
                               │
                ┌──────────────┴──────────────┐
                │                             │
           us-west-2                      eu-west-1
        ┌──────────────┐              ┌──────────────┐
        │ EKS prod-us  │              │ EKS prod-eu  │
        │ chrono-synth │              │ chrono-synth │
        └──────┬───────┘              └──────┬───────┘
               │                             │
        ┌──────▼──────┐               ┌──────▼──────┐
        │ RDS primary │ ◄── repl ──── │ RDS replica │
        │   (writer)  │               │  (reader)   │
        └─────────────┘               └─────────────┘
```

## Steady-state operation

- Route53 weighted DNS: 70% us-west, 30% eu-west.
- Both regions accept reads. Writes are routed to the **primary**
  (us-west in normal operation) via the application's connection
  string — eu-west pods read from their local replica but write
  cross-region. Acceptable: write latency ~80ms, dominated by the
  cross-region link, and writes are <5% of operations.
- KMS keys are multi-region replicas; the eu-west replica decrypts
  data encrypted with the us-west primary.
- Redis is region-local. Cache misses on failover are acceptable.

## Healthy ⇒ degraded transition

When us-west detects elevated 5xx for >5 minutes:

1. **PagerDuty fires** (Prometheus burn-rate alert from P0.2).
2. SRE on call confirms via Grafana that us-west is genuinely
   degraded (not a single-pod issue) — `sli:chrono_api_availability:err_rate1h`
   stays high after restart.
3. **Shift Route53 weights to 100% eu-west:**
   ```sh
   aws route53 change-resource-record-sets \
     --hosted-zone-id Z0123456789 \
     --change-batch file://failover-eu-only.json
   ```
   eu-west traffic share rises within DNS TTL (60s).
4. Investigate us-west cause; fix forward; gradually return weights
   to 70/30 over an hour to avoid a cold-cache thundering herd.

## Region failover (DR)

When us-west is **unrecoverable** (entire AZ outage, regional AWS
incident lasting >30min):

1. Confirm the outage at the AWS Health dashboard.
2. **Promote the eu-west RDS replica:**
   ```sh
   aws rds promote-read-replica \
     --db-instance-identifier chrono-synth-prod-eu-replica \
     --backup-retention-period 35 \
     --region eu-west-1
   ```
   Replica becomes a standalone primary. Async-replication lag at
   promotion time is the recovery RPO; expect <5s in steady state,
   document the actual measured value.
3. Update the application's connection-string secret to point at
   the new primary. ArgoCD or kubectl:
   ```sh
   kubectl -n chrono-synth edit secret chrono-synth-postgres
   ```
   Trigger a rolling restart of backend pods so they reconnect.
4. Shift Route53 weights to 100% eu-west (as above).
5. **Sit at single-region** until us-west is recovered and a fresh
   replica is provisioned in the failed-over direction (eu-west
   primary, us-west replica).
6. Once stable, plan the return to active-active in a maintenance
   window — failback requires a brief write freeze to swap the
   primary back.

## Application-level concerns

- **Idempotency**: every write goes through `idempotency_keys` (P3
  storage table). Replaying a write after a region flip is safe.
- **Audit log**: shipped per-tenant per-region; the cross-region
  reconciler runs nightly to merge.
- **Sync engine state**: the `runtime_recovery_worker` table tracks
  pending operations; on failover, the eu-west pods pick up where
  us-west left off via `claim_pending_recoveries(now)`.

## What we deliberately don't do

- **Synchronous cross-region replication.** Latency cost is
  prohibitive (every write +80-150ms). We accept the small RPO of
  async replication.
- **Cross-region Redis replication.** Cache layer is rebuilt from
  Postgres on promotion; the cold start hits LLM upstream more than
  it hits the DB and is bounded.
- **Active-active writes.** True dual-master Postgres requires
  conflict resolution (LWW or CRDTs) we don't have today. The
  primary is always single; only reads are local.

## Future direction (P3.6+)

- Aurora Global Database with sub-second cross-region replication
  (replaces the manual replica promotion with managed failover).
- Active-active **read** routing via Postgres logical replication +
  application-level read-only routing per tenant geography.
- Geo-pinned tenants (EU customers' writes stay in eu-west;
  US writes stay in us-west); reduces blast radius and helps GDPR
  data-residency.

## Drill cadence

Quarterly: simulate a us-west outage by shifting 100% of Route53
weight to eu-west for 1 hour. Verify:
- SLO dashboards show eu-west handling full load
- p95 latency stays under target (allowing for cold cache start)
- No 5xx leaks from session-affinity assumptions

Document each drill in `docs/operations/dr-drill-log.md`.
