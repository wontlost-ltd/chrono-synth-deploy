# Environment: dev (skeleton)

> Status: **scaffold only**. The full `main.tf` lands once the EKS
> module is implemented — the cluster is the load-bearing dependency
> for everything else.

## Expected layout

```hcl
# main.tf — composition root
provider "aws" {
  region = "us-west-2"
}

module "kms"   { source = "../../modules/kms-keyring"      ... }
module "vpc"   { source = "../../modules/vpc"              ... }  # planned, not yet defined
module "eks"   { source = "../../modules/eks-cluster"      ... }
module "rds"   { source = "../../modules/rds-postgres"     ... }
module "redis" { source = "../../modules/elasticache-redis" ... }
module "s3"    { source = "../../modules/s3-storage"       ... }
```

## Backend

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "chrono-synth-terraform-state-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "chrono-synth-terraform-locks"
    encrypt        = true
  }
}
```

State bucket + DynamoDB table bootstrapped manually — see
`docs/operations/terraform-bootstrap.md` (planned).

## Sizing defaults (dev profile)

- RDS: `db.t4g.medium`, single-AZ, 7-day backup
- Redis: `cache.t4g.small` × 1
- EKS: 2× `t4g.medium` workload nodes
- S3: 30-day Standard-IA transition, 90-day expiration (dev is
  short-lived)
