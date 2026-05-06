# Dev environment composition root.
#
# Wires the chrono-synth modules together. Sizing follows the per-env
# defaults baked into each module — dev uses the smallest variants so
# we can spin up + tear down in <30 min for short-lived feature work.
#
# Apply:
#   terraform init
#   terraform plan -out=tfplan
#   terraform apply tfplan
#
# Bootstrap (S3 state bucket + DynamoDB lock) is manual; see
# docs/operations/terraform-bootstrap.md.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Service     = "chrono-synth"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name        = "chrono-synth"
  environment = "dev"
  azs         = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source = "../../modules/vpc"

  name        = local.name
  environment = local.environment
  cidr_block  = "10.20.0.0/16"
  azs         = local.azs
}

module "kms_app_data" {
  source = "../../modules/kms-keyring"

  name        = "${local.name}-app-data"
  environment = local.environment

  # Service principals filled in once the EKS cluster's IRSA roles
  # exist; on first apply leave empty (the root account always retains
  # full kms:* per the module's policy).
  service_principal_arns = []
}

module "rds" {
  source = "../../modules/rds-postgres"

  name        = local.name
  environment = local.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  kms_key_id = module.kms_app_data.key_arn

  # Allow ingress from the EKS node security group.
  ingress_security_group_ids = [module.eks.node_security_group_id]
}

module "redis" {
  source = "../../modules/elasticache-redis"

  name        = local.name
  environment = local.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  kms_key_id = module.kms_app_data.key_arn

  ingress_security_group_ids = [module.eks.node_security_group_id]
}

module "eks" {
  source = "../../modules/eks-cluster"

  name        = local.name
  environment = local.environment

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  cluster_version = "1.32"

  # Dev: tiny single-AZ control plane fronted by a private endpoint.
  # endpoint_public_access stays off; operators reach the API via VPN
  # or the bastion (out of scope here).
  endpoint_public_access = false

  node_groups = {
    workload = {
      # Module's per-env defaults handle the rest (t4g.medium × 2 desired
      # for dev). Override here only if the workload needs spot.
      capacity_type = "ON_DEMAND"
    }
  }
}

module "s3_portability" {
  source = "../../modules/s3-storage"

  name        = "chrono-synth-portability-dev"
  environment = local.environment
  kms_key_id  = module.kms_app_data.key_arn

  # Portability exports retained 90 days in dev (vs 365 prod).
  lifecycle_expiration_days = 90
  lifecycle_transition_days = 30
  versioning_enabled        = true
}

module "s3_compliance_evidence" {
  source = "../../modules/s3-storage"

  name        = "chrono-synth-compliance-evidence-dev"
  environment = local.environment
  kms_key_id  = module.kms_app_data.key_arn

  # Compliance evidence kept long even in dev (audit drills sometimes
  # need it). 365 days, no transition.
  lifecycle_expiration_days = 365
  lifecycle_transition_days = 90
  versioning_enabled        = true
}

module "compliance_evidence" {
  source = "../../modules/compliance-evidence"

  name        = local.name
  environment = local.environment

  evidence_bucket_name        = module.s3_compliance_evidence.bucket_name
  evidence_bucket_arn         = module.s3_compliance_evidence.bucket_arn
  evidence_bucket_kms_key_arn = module.kms_app_data.key_arn

  oidc_provider_arn = module.eks.oidc_provider_arn
  # OIDC issuer URL output is the full https:// URL; trim the prefix
  # for the trust policy condition (which expects the bare host+path).
  oidc_issuer_url = replace(module.eks.oidc_issuer_url, "https://", "")
}
