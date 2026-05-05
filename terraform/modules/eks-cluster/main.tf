# EKS cluster module — thin wrapper around terraform-aws-modules/eks/aws v20.
#
# Why wrap and not pull the upstream directly:
#   - Per-env sizing defaults that callers should rarely have to think
#     about.
#   - Hardened control-plane defaults (private endpoint, all CloudWatch
#     log types, encryption-at-rest with caller's KMS).
#   - Consistent tagging via the merged_tags pattern shared with
#     rds-postgres / elasticache-redis / s3-storage.
#
# What this module deliberately does not do:
#   - Network: bring your own VPC + subnets. The VPC module is its own
#     follow-up; we don't want to couple cluster lifecycle to networking.
#   - Add-on management beyond the EKS-managed defaults (vpc-cni, coredns,
#     kube-proxy). External-DNS, cert-manager, ArgoCD itself land via
#     ArgoCD ApplicationSets ([ADR 0020]) — terraform should not race with
#     ArgoCD over the same kube-system surface.
#   - Karpenter: the upstream module supports it, but the decision between
#     Karpenter and the cluster-autoscaler is its own ADR and PR.

locals {
  is_prod    = var.environment == "prod"
  is_staging = var.environment == "staging"

  # Per-env defaults: dev=2 small, staging=3 medium, prod=6 large.
  default_node_size = (
    local.is_prod ? { instance_types = ["m6g.large"], min = 3, max = 10, desired = 6 }
    : local.is_staging ? { instance_types = ["m6g.medium"], min = 2, max = 5, desired = 3 }
    : { instance_types = ["t4g.medium"], min = 1, max = 3, desired = 2 }
  )

  # Resolve each user-supplied node group against the env defaults.
  resolved_node_groups = {
    for k, v in var.node_groups : k => {
      instance_types = coalesce(v.instance_types, local.default_node_size.instance_types)
      min_size       = coalesce(v.min_size, local.default_node_size.min)
      max_size       = coalesce(v.max_size, local.default_node_size.max)
      desired_size   = coalesce(v.desired_size, local.default_node_size.desired)
      capacity_type  = coalesce(v.capacity_type, "ON_DEMAND")
      labels         = v.labels
      taints         = v.taints
    }
  }

  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "eks-cluster"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

# Cluster-encryption KMS key. Generated here rather than received as a
# variable because the cluster KMS lifecycle is bounded by the cluster
# itself; if the cluster is destroyed, this key should also be marked
# for deletion. Application-data CMKs (for RDS, S3) are caller-managed.
resource "aws_kms_key" "eks" {
  description             = "Chrono Synth EKS cluster (${var.name}-${var.environment}) secret encryption"
  enable_key_rotation     = true
  deletion_window_in_days = local.is_prod ? 30 : 7
  tags                    = local.merged_tags
}

resource "aws_kms_alias" "eks" {
  name          = "alias/chrono-synth-eks-${var.name}-${var.environment}"
  target_key_id = aws_kms_key.eks.key_id
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr Upstream module's worker-node SG rule
# allows egress to 0.0.0.0/0 because nodes need to reach the public internet
# (image pulls, OS updates, AWS API endpoints) via NAT. Cilium / Calico
# layer-7 policies restrict the actual workload egress; the SG rule here is
# necessary plumbing.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "${var.name}-${var.environment}"
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  cluster_endpoint_public_access       = var.endpoint_public_access
  cluster_endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  cluster_endpoint_private_access      = true

  # Encrypt Kubernetes Secrets at rest with our CMK.
  cluster_encryption_config = {
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  # Send all available control-plane log types to CloudWatch.
  # Retention 30d in dev/staging, 90d in prod.
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = local.is_prod ? 90 : 30

  # IRSA for in-cluster service accounts to assume IAM roles.
  enable_irsa = true

  # Default add-ons; pin versions implicitly via the module's catalog.
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # Managed node groups
  eks_managed_node_groups = {
    for k, v in local.resolved_node_groups : k => {
      instance_types = v.instance_types
      capacity_type  = v.capacity_type

      min_size     = v.min_size
      max_size     = v.max_size
      desired_size = v.desired_size

      # Workload-class taints + labels passthrough.
      labels = v.labels
      taints = v.taints

      # AL2023 + ARM-friendly default; overridden when instance_types
      # contain x86 shapes.
      ami_type = startswith(v.instance_types[0], "m6g.") || startswith(v.instance_types[0], "t4g.") || startswith(v.instance_types[0], "r6g.") ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"

      # Disk: GP3 at 100 GB; pods using emptyDir / overlay need it.
      disk_size = 100
    }
  }

  tags = local.merged_tags
}
