# Hybrid Reference Architecture

## Overview

Hybrid deploys the ChronoSynth control plane on Wontlost-managed infrastructure while tenant data (databases, object storage, encryption keys) lives on tenant-owned infrastructure. You own your data plane; we operate the API surface.

## Deployment Model

```
Wontlost Cloud                    Your Infrastructure
┌──────────────────────┐          ┌───────────────────────────────┐
│  chrono-synth-os API │◄────────►│  Tenant PostgreSQL / Aurora   │
│  chrono-synth-web    │          │  Tenant Redis / ElastiCache   │
│  Observability stack │          │  Tenant S3 / GCS / Blob       │
│                      │          │  Tenant KMS / Vault           │
└──────────────────────┘          └───────────────────────────────┘
         ↑
  Auth / API calls
  from your clients
```

## Data Plane Ownership

| Component | Owner | Location |
|-----------|-------|----------|
| API compute | Wontlost | Managed cloud |
| Tenant database | You | Your VPC / cloud |
| Encryption keys | You | Your KMS / Vault |
| Blob/object storage | You | Your bucket |
| Kafka namespace | You | Your Redpanda / MSK |
| Audit log export | You | Your SIEM / S3 |

## Configuration

### Step 1 — Declare Deployment Profile

```bash
curl -X PUT "$BACKEND_URL/api/v1/admin/deployment/profile" \
  -H "Authorization: Bearer $ADMIN_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "deploymentMode": "dedicated_db",
    "databaseIsolationMode": "dedicated",
    "kafkaNamespace": "acme-corp",
    "encryptionMode": "tenant_dedicated",
    "kmsKeyRef": "arn:aws:kms:us-east-1:123456789:key/abc-123"
  }'
```

### Step 2 — Configure BYOK

Apply the addon matching your KMS:

```bash
# AWS KMS
kubectl apply -k k8s/addons/byok-aws-kms
# Requires: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, KMS_KEY_ARN in secrets

# Azure Key Vault
kubectl apply -k k8s/addons/byok-azure-kv

# GCP Cloud KMS
kubectl apply -k k8s/addons/byok-gcp-kms

# HashiCorp Vault
kubectl apply -k k8s/addons/byok-vault
```

### Step 3 — Configure BYOS (optional)

```bash
# Route knowledge/blob data to your own bucket
kubectl apply -k k8s/addons/byos-s3
# Set: AWS_S3_BUCKET, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

### Step 4 — Configure SCIM Provisioning

```bash
# Generate a SCIM token for your IdP (Okta, Azure AD, etc.)
curl -X POST "$BACKEND_URL/api/v1/admin/deployment/scim-token" \
  -H "Authorization: Bearer $ADMIN_JWT"
# → { "token": "scim_..." }
```

Point your IdP SCIM endpoint at: `https://api.chronosynth.com/scim/v2`

## Network Requirements

| Direction | Protocol | Purpose |
|-----------|----------|---------|
| Wontlost API → Your DB | TCP 5432 | Tenant database writes |
| Wontlost API → Your KMS | HTTPS 443 | Key operations |
| Your clients → Wontlost API | HTTPS 443 | API calls |
| Wontlost API → Your Kafka | TCP 9092 | Observability events |

Your database must allow inbound from Wontlost's egress IP range (provided in tenant onboarding).

## Data Sovereignty Guarantees

- Raw persona/memory data is written only to your database, never to Wontlost storage
- Encryption/decryption happens at the tenant boundary using your KMS key — Wontlost never holds plaintext
- Audit logs are streamed to your Kafka namespace and can be exported to your SIEM
- Portability pack export (`POST /api/v2/portability/export`) includes all tenant data, encrypted with your key

## Checklist

- [ ] Deployment profile set to `dedicated_db` + `tenant_dedicated` encryption
- [ ] BYOK addon applied and KMS connectivity verified (`scripts/validate-k8s.sh`)
- [ ] Tenant database network policy allows Wontlost egress IPs
- [ ] SCIM token configured in your IdP
- [ ] BYOS bucket configured (if using knowledge/blob features)
- [ ] Kafka namespace created and topic policies applied
- [ ] Portability export roundtrip tested (`scripts/portability-conformance.sh`)
- [ ] Audit log export verified in your SIEM
