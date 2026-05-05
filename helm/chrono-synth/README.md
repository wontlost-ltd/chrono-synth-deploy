# chrono-synth Helm chart

Helm distribution of the Chrono Synth platform. Parallels the
`k8s/`-based kustomize manifests for customers who prefer Helm.

## When to use this vs kustomize

| Audience | Use |
|----------|-----|
| Self-hosted customers, on-prem clusters | **Helm** (this chart) |
| Internal Wontlost-managed deployments (dev/staging/prod) | **kustomize + ArgoCD** (`k8s/`) |

The two paths emit functionally equivalent manifests for the backend and
frontend; the kustomize path additionally bundles observability addons,
SLO recording rules, and the GitOps machinery, which Helm consumers are
expected to wire up via their own controllers if they want them.

## Requirements

- Kubernetes 1.28+
- Helm 3.12+
- An external PostgreSQL (RDS or self-managed) and Redis (ElastiCache or
  self-managed). The chart **does not provision them** — see
  `terraform/modules/rds-postgres/` and `terraform/modules/elasticache-redis/`.
- A `Secret` per service holding the connection string (default names:
  `chrono-synth-postgres`, `chrono-synth-redis`). Wire via External Secrets
  Operator from your secret store of choice.

## Install

```bash
# 1. Create the connection-string secrets
kubectl create namespace chrono-synth
kubectl -n chrono-synth create secret generic chrono-synth-postgres \
  --from-literal=connection-string="postgres://chrono_admin:..."
kubectl -n chrono-synth create secret generic chrono-synth-redis \
  --from-literal=url="rediss://:auth-token@redis.example.com:6379"

# 2. Install the chart
helm install chrono-synth ./helm/chrono-synth \
  --namespace chrono-synth \
  --set namespace.createNamespace=false \
  --set backend.image.tag=v2.0.0 \
  --set frontend.image.tag=v2.0.0

# 3. Verify
helm test chrono-synth -n chrono-synth  # planned; not yet shipped
kubectl -n chrono-synth get pods
```

Pin image tags explicitly. The Kyverno policy
`disallow-image-latest-tag` rejects `:latest` images in compliant
clusters.

## Per-environment overrides

Provide an overrides file:

```bash
helm upgrade chrono-synth ./helm/chrono-synth \
  --namespace chrono-synth \
  -f values-prod.yaml
```

`values-prod.yaml` example:

```yaml
backend:
  replicas: 6
  resources:
    requests: { cpu: 500m, memory: 512Mi }
    limits:   { cpu: 2000m, memory: 2Gi }

ingress:
  enabled: true
  className: nginx
  hosts:
    - host: api.chrono.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: chrono-synth-tls
      hosts: [api.chrono.example.com]
```

## Values reference

See [`values.yaml`](values.yaml). Top-level groups:

| Group | Purpose |
|-------|---------|
| `namespace` | name + PSA labels + createNamespace toggle |
| `backend` | image / replicas / resources / probes / security context |
| `frontend` | image / replicas / resources |
| `externalServices` | secret names for postgres + redis connection strings |
| `ingress` | optional ingress; defaults to disabled |
| `networkPolicy` | default-deny baseline; default enabled |

## Compatibility with the kustomize path

The Helm chart and kustomize path can be installed into the same cluster
**only in different namespaces**. They will both create resources named
`chrono-synth-os` etc., and Kubernetes will reject the duplicate names if
they collide. The chart helper `chrono-synth.fullname` keeps the names
release-prefixed (`<release>-backend`, `<release>-frontend`) — a partial
mitigation, but if you need true side-by-side, use distinct namespaces.

## Roadmap

- `helm test` smoke test pod (planned)
- HPA template behind a `hpa.enabled` flag (mirrors `k8s/overlays/prod/hpa.yaml`)
- Optional bundling of the SLO addons (recording rules + alerts) once
  the operator-pattern decision is made

## License

AGPL-3.0 — same as the rest of the deploy repo. See repo root LICENSE.
