# K8s Add-on Overlays

Optional Kustomize overlays for enterprise BYOK (Bring Your Own Key) and BYOS (Bring Your Own Storage) configuration. Apply these on top of any environment overlay.

## Usage

Create a composite overlay (e.g. `k8s/overlays/prod-byok-aws/kustomization.yaml`):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ../prod              # base environment overlay
  - ../../addons/byok-aws-kms
  - ../../addons/byos-s3
```

Then deploy:

```bash
kubectl apply -k k8s/overlays/prod-byok-aws/
```

## Available Add-ons

### BYOK — Bring Your Own Key

| Directory | Provider | Auth method |
|-----------|----------|-------------|
| `byok-aws-kms` | AWS KMS | IAM role / IRSA (recommended) or static credentials |
| `byok-gcp-kms` | GCP Cloud KMS | Workload Identity (recommended) or service account JSON |
| `byok-azure-kv` | Azure Key Vault | Managed Identity (recommended) or service principal |
| `byok-vault` | HashiCorp Vault (transit) | Kubernetes auth (recommended) or token |

Each add-on:
1. Creates a `Secret` with provider-specific credentials
2. Patches `backend-config` ConfigMap to set `CHRONO_KMS_PROVIDER`

### BYOS — Bring Your Own Storage

| Directory | Provider | Auth method |
|-----------|----------|-------------|
| `byos-s3` | AWS S3 (+ S3-compatible) | IAM role / IRSA (recommended) or static credentials |
| `byos-gcs` | Google Cloud Storage | Workload Identity (recommended) or service account JSON |
| `byos-azure-blob` | Azure Blob Storage | Managed Identity (recommended) or connection string |

Each add-on:
1. Creates a `Secret` with provider-specific credentials
2. Patches `backend-config` ConfigMap to set `CHRONO_STORAGE_PROVIDER`

## Rotating Credentials

1. Update the Secret values (use `kubectl create secret --dry-run=client -o yaml | kubectl apply -f -` for zero-downtime).
2. Trigger a rolling restart: `kubectl rollout restart deployment/chrono-synth-os -n chrono-synth`.
3. Verify the new provider is active via the Admin API health endpoint.
