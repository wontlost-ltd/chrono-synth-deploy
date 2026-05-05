# Terraform IaC — chrono-synth-deploy (P1.1 starter)

Cloud resource provisioning for the Chrono Synth platform. The full
P1.1 deliverable is multi-week (eks/gke/aks cluster, full RDS/Redis/S3/
KMS modules, environments, terratest); this directory ships the
**skeleton + a working RDS-postgres module + s3-storage module + the
plan-on-PR workflow** so the layout is conventional and engineers can
extend without bikeshedding the structure.

## Layout

```
terraform/
├── modules/
│   ├── rds-postgres/      ✅ shipped
│   ├── s3-storage/        ✅ shipped
│   ├── eks-cluster/       (skeleton: README + variables only)
│   ├── elasticache-redis/ (skeleton)
│   └── kms-keyring/       (skeleton)
└── environments/
    ├── dev/               (skeleton)
    ├── staging/           (skeleton)
    └── prod/              (skeleton)
```

Each module follows the [terraform-aws-modules](https://github.com/terraform-aws-modules)
convention: `main.tf` + `variables.tf` + `outputs.tf` + `versions.tf` +
optional `README.md`. Variables are typed with `validation` blocks
where the value range matters (e.g., RDS engine version pinning).

## Backend

State lives in S3 with DynamoDB locking — the standard AWS pattern.
Configure via `backend.tf` per environment:

```hcl
terraform {
  backend "s3" {
    bucket         = "chrono-synth-terraform-state-prod"
    key            = "prod/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "chrono-synth-terraform-locks"
    encrypt        = true
  }
}
```

The bucket + DynamoDB table are bootstrapped manually (chicken-and-egg)
once per environment. Documented in
`docs/operations/terraform-bootstrap.md` (planned).

## Tools

- `tflint` — linting; config in `.tflint.hcl` at repo root.
- `tfsec` — security scanning; runs in CI.
- `terratest` — integration tests against ephemeral cloud resources;
  out of scope for the starter, planned alongside the EKS module.
- `infracost` — cost diff in PR comments; runs in CI alongside
  terraform plan.

## CI

`.github/workflows/terraform.yml`:
- On PR: run `terraform fmt -check`, `tflint`, `tfsec`, then
  `terraform plan` on each environment that touches changed files.
  Comment the plan output (and infracost diff) on the PR.
- On merge to main: run `terraform apply` against the dev environment
  only (auto-approve). Staging + prod require manual workflow_dispatch
  with environment protection rules requiring reviewer approval.

## What's not here yet (tracked)

- Concrete EKS module body (the cluster topology decision is its own
  PR — node-group shapes, AMI pinning, IRSA setup).
- Multi-cloud locals (GKE / AKS); the structure assumes AWS first
  with cloud-agnostic abstractions added per-module.
- terratest integration; depends on EKS module landing first.
- `terraform apply` GHA workflow; we ship plan-on-PR but only
  document the apply path until reviewer protections are configured.

See `enterprise-readiness-2026.md` § P1.1 for the full target state.
