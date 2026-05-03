# Self-Host Reference Architecture

## Overview

Self-host deploys all ChronoSynth services on infrastructure you own and operate. You control every layer: compute, database, encryption keys, network, and backups. No data leaves your perimeter.

## Deployment Model

```
Your Infrastructure
┌─────────────────────────────────────────────────────┐
│  Ingress (nginx / Traefik / Caddy)                  │
│     ↓                                               │
│  chrono-synth-web  (frontend + nginx proxy)         │
│     ↓                                               │
│  chrono-synth-os   (backend API + workers)          │
│     ↓                   ↓             ↓             │
│  PostgreSQL         Redis          Redpanda/Kafka    │
│                                                     │
│  Prometheus + Grafana + Jaeger  (observability)     │
└─────────────────────────────────────────────────────┘
```

## Deployment Options

| Option | When to Use |
|--------|-------------|
| **Podman (single node)** | Development, small team, air-gapped |
| **k3s overlay (dev/staging)** | Homelab, private cloud, CI preview |
| **k8s prod overlay** | Multi-node HA, enterprise on-prem |

## Quick Start (Podman)

```bash
# 1. Clone deploy repo
git clone https://github.com/wontlost-ltd/chrono-synth-deploy
cd chrono-synth-deploy

# 2. Generate secrets
./deploy.sh secrets

# 3. Start all services
./deploy.sh podman up

# 4. Verify
./scripts/e2e-test.sh
```

## Kubernetes (k3s / k8s)

```bash
# Development — single replica, low resources
make k3s-dev ENV=dev

# Production — HA replicas, HPA, PDB
make k3s-prod ENV=prod
```

## Required Secrets

| Secret | Description | How to Generate |
|--------|-------------|-----------------|
| `CHRONO_ENCRYPTION_MASTER_KEY` | AES-256-GCM master key | `openssl rand -base64 32` |
| `CHRONO_JWT_SECRET` | JWT signing key | `openssl rand -hex 32` |
| `POSTGRES_PASSWORD` | Database password | `openssl rand -hex 20` |
| `REDIS_PASSWORD` | Cache password | `openssl rand -hex 20` |

All secrets are injected via Kubernetes Secrets or Podman env files — never baked into images.

## BYOK (Bring Your Own Key)

For tenant-dedicated encryption, apply the appropriate addon:

```bash
# AWS KMS
kubectl apply -k k8s/addons/byok-aws-kms

# HashiCorp Vault
kubectl apply -k k8s/addons/byok-vault
```

See `docs/production-readiness.md` for the full hard gates checklist.

## BYOS (Bring Your Own Storage)

Route knowledge/blob data to your own object store:

```bash
# AWS S3
kubectl apply -k k8s/addons/byos-s3

# Google Cloud Storage
kubectl apply -k k8s/addons/byos-gcs

# Azure Blob
kubectl apply -k k8s/addons/byos-azure-blob
```

## Observability Stack

All services expose metrics at `/metrics/prometheus`. Prometheus scrapes on the schedule defined in `prometheus-scrape-jobs.yml.tpl`. Grafana dashboards and Jaeger traces are included in the default stack.

## Network Policy

`k8s/base/network-policy.yaml` restricts inter-service traffic to declared paths only. Backend pods cannot reach the internet directly in the default policy.

## Upgrade Path

1. Pull new images: `make build push TAG=<version>`
2. Apply manifests: `make k3s-prod`
3. Verify: `./scripts/health-check.sh`
4. Roll back: `kubectl rollout undo deployment/chrono-synth-os`

## Checklist

- [ ] All secrets injected (not in configmaps or image env)
- [ ] `CHRONO_AUTH_ENABLED=true` in production overlay
- [ ] `CHRONO_ENCRYPTION_ENABLED=true` in production overlay
- [ ] TLS configured on ingress
- [ ] Prometheus scrape auth enabled
- [ ] Backup job configured for PostgreSQL
- [ ] `./scripts/validate-k8s.sh` passes
- [ ] `./scripts/e2e-test.sh` passes against staging before promoting to prod
