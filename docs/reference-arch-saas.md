# SaaS Reference Architecture

## Overview

SaaS is the fully-managed mode. Wontlost operates all infrastructure — compute, database, encryption, observability. Tenants access ChronoSynth through the web app, API, mobile app, or desktop app without managing any infrastructure.

## Deployment Model

```
Wontlost Managed Cloud
┌────────────────────────────────────────────────────────┐
│                                                        │
│  CDN (Cloudflare)                                      │
│     ↓                                                  │
│  chrono-synth-web  (frontend + nginx)                  │
│     ↓                                                  │
│  chrono-synth-os   (API + workers)  × N replicas       │
│     ↓           ↓            ↓            ↓            │
│  PostgreSQL   Redis      Redpanda      S3/GCS          │
│  (shared or dedicated per tier)                        │
│                                                        │
│  Prometheus + Grafana + Jaeger + SIEM                  │
│                                                        │
└────────────────────────────────────────────────────────┘
         ↑
  Web / API / Mobile / Desktop clients
```

## Tenant Isolation Tiers

| Tier | DB Isolation | Encryption | Kafka | Target |
|------|-------------|------------|-------|--------|
| **Starter** | Shared schema | Platform key | Shared topic | Individuals, small teams |
| **Team** | Dedicated schema | Platform key | Shared topic | Growing teams |
| **Business** | Dedicated DB | Platform key | Dedicated namespace | Companies |
| **Enterprise** | Dedicated DB | Tenant BYOK | Dedicated namespace | Regulated industries |

Tier is set via `deploymentMode` in the tenant deployment profile.

## Onboarding

### Self-service (Starter / Team)

1. Sign up at `https://app.chronosynth.com`
2. Invite team members via email or SCIM
3. Connect integrations (Slack, Notion, etc.)
4. Export your data any time via **Settings → Portability**

### Assisted (Business / Enterprise)

1. Contact sales for tenant provisioning
2. Wontlost creates a dedicated deployment profile:
   ```bash
   PUT /api/v1/admin/deployment/profile
   { "deploymentMode": "dedicated_db", "encryptionMode": "tenant_dedicated", ... }
   ```
3. Configure SCIM with your IdP
4. (Enterprise) Apply BYOK addon if using your own KMS

## Multi-Runtime Clients

All runtimes connect to the same SaaS API:

| Runtime | Auth | Sync |
|---------|------|------|
| Web (chrono-synth-web) | JWT via cookie/header | Server-authoritative |
| Mobile (Expo) | JWT via Keychain/Keystore | Push-triggered + background |
| Desktop (Tauri) | JWT via OS keychain | Background sync + tray |
| CLI | API key | Pull on demand |

## Data Portability

Tenants can export all their data at any time — no vendor lock-in:

```bash
# Request export
POST /api/v2/portability/export
→ { "exportId": "...", "status": "queued" }

# Download when ready
GET /api/v2/portability/export/{exportId}/download
→ <signed download URL for .chrono-pack file>
```

The `.chrono-pack` format is open — it can be imported into any runtime (self-host, desktop, or another SaaS instance).

## SLA and Compliance

| Concern | SaaS Commitment |
|---------|-----------------|
| Uptime | 99.9% (Starter/Team), 99.95% (Business/Enterprise) |
| Data residency | US-East (default), EU (on request) |
| Encryption at rest | AES-256-GCM, key per tenant |
| Encryption in transit | TLS 1.3 |
| SOC 2 Type II | In progress |
| GDPR / DSR | Full export + deletion via API |

## Observability

Tenants see their own metrics via the Grafana dashboard embedded in the app. Wontlost's ops team monitors the shared stack. Enterprise tenants can enable Kafka export to stream audit/observability events to their own SIEM.

## Rollback / Incident Model

- Canary deploys with automatic rollback on error rate spike
- P0 incidents: rollback within 15 minutes, tenant notification within 30 minutes
- Data backup: hourly snapshots, 30-day retention, point-in-time recovery on Business+

## Checklist (Wontlost Ops)

- [ ] Tenant deployment profile created and validated
- [ ] Isolated DB provisioned for Business/Enterprise tiers
- [ ] SCIM endpoint tested with tenant IdP
- [ ] BYOK addon applied for Enterprise tenants with their own KMS
- [ ] Portability export roundtrip verified for tenant
- [ ] Canary deployment policy active
- [ ] Tenant-scoped Grafana dashboard accessible
- [ ] DSR (data subject request) flow tested
