# VPC module — wraps terraform-aws-modules/vpc/aws v6.x with chrono-synth defaults.
#
# Topology per environment:
#   dev      → 3 AZs, 1 NAT gateway (cost-optimised)
#   staging  → 3 AZs, 3 NAT gateways (one per AZ — HA)
#   prod     → 3 AZs, 3 NAT gateways
#
# Subnets per AZ:
#   - 1 public  /22 (~1k IPs each; LB only)
#   - 1 private /20 (~4k IPs each; workloads + RDS + ElastiCache)
# Total /16 budget: 3 * (/22 + /20) = ~15k IPs allocated; rest reserved.
#
# Tags include the EKS-required label (kubernetes.io/role/elb on public,
# /internal-elb on private) so EKS auto-discovers subnets for LB
# provisioning. Tag value MUST be `1`, not `true`.

locals {
  is_prod    = var.environment == "prod"
  is_staging = var.environment == "staging"
  ha_nat     = local.is_prod || local.is_staging

  # 3 AZs assumed; subnet-cidrs derived from the /16 base.
  public_subnets  = [for i in range(length(var.azs)) : cidrsubnet(var.cidr_block, 6, i)]     # /22 each
  private_subnets = [for i in range(length(var.azs)) : cidrsubnet(var.cidr_block, 4, i + 8)] # /20 each, offset to avoid public range

  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "vpc"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${var.name}-${var.environment}"
  cidr = var.cidr_block

  azs             = var.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = !local.ha_nat
  one_nat_gateway_per_az = local.ha_nat

  enable_dns_hostnames = true
  enable_dns_support   = true

  # VPC Flow Logs to CloudWatch — required for the security review +
  # the chaos-mesh DNS drill (we need to observe traffic patterns
  # during the failure window).
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = local.is_prod ? 90 : 30

  # EKS-friendly subnet tags (auto-discovery by aws-load-balancer-controller).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.merged_tags
}
