# GitOps Runbook

This runbook describes how Chrono Synth's three environments (dev / staging /
prod) are reconciled by ArgoCD, what to do when a sync fails, and how to make
emergency changes when the platform team is asleep.

Pair with:

- [`argocd/install/argocd-install.yaml`](../../argocd/install/argocd-install.yaml) — bootstrap manifest
- [`argocd/projects/chrono-synth.yaml`](../../argocd/projects/chrono-synth.yaml) — AppProject (RBAC + resource scopes)
- [`argocd/applicationsets/chrono-synth.yaml`](../../argocd/applicationsets/chrono-synth.yaml) — Application generator
- [SLO runbook](../../../chrono-synth-os/docs/operations/slo-runbook.md) — when sync trouble correlates with SLO breach

## Topology

```
                        ┌──────────────┐
                        │  GitHub main │
                        │  (this repo) │
                        └──────┬───────┘
                               │ poll every 3m
                               ▼
   ┌──────────────────────────────────────────────────┐
   │                   ArgoCD                         │
   │  AppProject: chrono-synth (RBAC + scope)         │
   │  ApplicationSet → 3 generated Applications:      │
   │    chrono-synth-dev      auto-sync + auto-prune  │
   │    chrono-synth-staging  auto-sync               │
   │    chrono-synth-prod     manual sync             │
   └──────────────────────────────────────────────────┘
                               │
                               ▼
                  one Kubernetes cluster, three namespaces
```

Each Application points at the same repo + branch (`main`), differing only
in `path` (the overlay) and `syncPolicy`. ArgoCD pulls the manifests, applies
them server-side, and writes back the live state. SelfHeal=true everywhere
means a hand-edit on the cluster gets reverted within 3 minutes.

## Sync policy by environment

| Env     | auto-sync | auto-prune | self-heal | typical flow                              |
| ------- | --------- | ---------- | --------- | ----------------------------------------- |
| dev     | ✅         | ✅          | ✅         | merge to main → dev updates within 3 min  |
| staging | ✅         | ❌          | ✅         | merge → staging updates; orphans warn-only |
| prod    | ❌         | ❌          | ✅         | merge → ArgoCD shows OutOfSync → click sync |

**Why self-heal on prod**: self-heal only acts when the cluster diverges from
the *currently-synced* git ref. It does not pull new commits — that's still
manual. So self-heal protects against drift from a human kubectl, not against
unreviewed git changes.

## Routine: rolling out a change

1. Open a PR against `main` of `chrono-synth-deploy` modifying the relevant
   overlay (or `k8s/base/` for cross-env changes).
2. Reviewer approves; PR merges.
3. **dev**: ArgoCD auto-syncs within 3 min. Watch in the UI or via:
   ```sh
   argocd app get chrono-synth-dev --output wide
   ```
   Hash mismatch + green = synced and healthy.
4. **staging**: same — auto-sync. If the change is destructive (ConfigMap
   key removed), watch for orphan warnings: those resources need a manual
   `argocd app actions run chrono-synth-staging delete --resource ...`.
5. **prod**: ArgoCD UI shows the app as `OutOfSync`. After staging has run
   green for ≥30 min and the smoke-test pipeline has passed, click `Sync`.
   The sync will re-apply server-side; pods roll using the rolling-update
   strategy already in the deployments.

## Emergency: cluster has drifted (someone ran kubectl apply)

Self-heal will revert the change within 3 minutes by default. If you need
to keep the hand-edit (e.g., debugging a live issue):

1. Pause auto-sync on the affected application:
   ```sh
   argocd app set chrono-synth-prod --sync-policy none
   ```
   This disables auto-sync **and** self-heal for that app.
2. Make your change with kubectl. Document why in `#sre-oncall`.
3. When done, re-enable:
   ```sh
   argocd app set chrono-synth-prod --sync-policy automated --self-heal
   ```
   ArgoCD will reconcile back to git on the next poll.

If the hand-edit needs to become permanent: open a PR. Don't leave the app
in paused-sync state for >24 h.

## Emergency: rollback

```sh
# Show recent syncs
argocd app history chrono-synth-prod
# Each entry has an id and the git ref it was synced to

# Roll back to revision id 7 (for example)
argocd app rollback chrono-synth-prod 7
```

This re-applies the manifests from that historical commit. It does **not**
revert the git history. The next git push to main will move the app forward
again — so file a revert PR alongside the rollback.

## Emergency: ArgoCD itself is wedged

ArgoCD pods crashlooping or controller refusing to reconcile:

1. Check pods: `kubectl -n argocd get pods`
2. Check controller logs:
   `kubectl -n argocd logs deploy/argocd-application-controller --tail=200`
3. Common causes + fixes:
   - **Repo creds expired**: rotate the GitHub token used by the
     `argocd-secret`. UI: Settings → Repos → re-connect.
   - **Redis OOM**: scale `argocd-redis` memory; restart.
   - **Webhook spam**: disable repo webhooks temporarily, fall back to
     polling, find the offending repo.
4. While ArgoCD is down, you can apply manifests directly:
   `kubectl apply -k k8s/overlays/prod`. This skips RBAC and audit; only do
   it during a declared incident.

## Failure modes & alerts

We don't ship dedicated ArgoCD alerts yet (planned in P1.2 follow-up). Until
then, watch:

- **`argocd-application-controller` pod restart count** — rising = bug
- **Application status `Degraded` or `OutOfSync` >24h** — staging/prod only
- **`argocd-server` 5xx rate** — usually upstream API throttling

Surface these via the existing Grafana SLO board (`Chrono SLO` dashboard,
add a panel from `kube_pod_container_status_restarts_total{namespace="argocd"}`).

## Drift detection drill (quarterly)

1. Pick a non-critical resource in dev (e.g., a HPA min replicas).
2. Edit it manually: `kubectl -n chrono-synth edit hpa backend`.
3. Set min replicas to a wrong value, save.
4. Wait ≤3 minutes.
5. Verify: `kubectl -n chrono-synth get hpa backend -o yaml` should show the
   git value, not your edit.
6. Verify in ArgoCD UI: the resource should show a brief OutOfSync flicker
   then return to Synced.

If self-heal didn't kick in within 5 minutes: open a P1 incident — drift
protection is broken.

## RBAC

GitHub team membership controls access (mapped in `argocd-rbac-cm`):

- `wontlost-ltd:platform` → role `platform-admin` (full)
- `wontlost-ltd:engineering` → role `developer` (read + sync, no delete)

Adding a new team:

1. Edit `argocd/install/argocd-install.yaml` patch for `argocd-rbac-cm`.
2. Add `g, <org>:<team>, role:<role>` lines.
3. PR + merge; ArgoCD picks up the new RBAC on next reconcile (≤3 min).

## Onboarding a new environment

1. Add a new entry to the `generators.list.elements` block in
   `argocd/applicationsets/chrono-synth.yaml`. Pattern:
   ```yaml
   - name: sandbox
     overlayPath: k8s/overlays/sandbox
     namespace: chrono-synth-sandbox
     autoSync: true
     autoPrune: true
     revision: main
   ```
2. Create the corresponding `k8s/overlays/sandbox/kustomization.yaml`.
3. Merge. ApplicationSet generates `chrono-synth-sandbox`; ArgoCD creates
   the namespace and reconciles.
