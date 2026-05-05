# ElastiCache Redis module — replication group with TLS + auth token.
#
# Defaults follow the per-environment convention:
#   dev      → cache.t4g.small × 1 (no replication, single AZ)
#   staging  → cache.r7g.large × 2 (1 primary + 1 replica, multi-AZ)
#   prod     → cache.r7g.large × 3 (1 primary + 2 replicas, multi-AZ + auto-failover)
#
# Always-on:
#  - Encryption in transit (TLS, port 6379 with auth token)
#  - Encryption at rest (KMS, caller-supplied key)
#  - Auth token via Secrets Manager
#  - Snapshot retention: 1 day (dev), 7 days (staging/prod)
#
# What this module deliberately doesn't do:
#  - Cross-region replication (P3.6 territory).
#  - Custom parameter groups beyond the defaults; if a workload needs
#    notify-keyspace-events or maxmemory-policy tuning, pass the
#    parameter_group_name into a follow-up override module.

locals {
  is_prod    = var.environment == "prod"
  is_staging = var.environment == "staging"

  default_node_type = (
    local.is_prod ? "cache.r7g.large"
    : local.is_staging ? "cache.r7g.large"
    : "cache.t4g.small"
  )
  resolved_node_type = coalesce(var.node_type, local.default_node_type)

  default_num_cache_clusters = (
    local.is_prod ? 3
    : local.is_staging ? 2
    : 1
  )
  resolved_num_cache_clusters = coalesce(var.num_cache_clusters, local.default_num_cache_clusters)

  multi_az = local.resolved_num_cache_clusters > 1
  automatic_failover = local.multi_az  # ElastiCache requires multi-AZ for auto-failover

  snapshot_retention_days = (
    local.is_prod || local.is_staging ? 7 : 1
  )

  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "elasticache-redis"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

# Auth token — random; kept in Secrets Manager.
# AWS spec: 16-128 chars, no /, ', ", @, or whitespace.
resource "random_password" "auth" {
  length           = 64
  special          = true
  override_special = "!#$%&()*+,-.:;<=>?[]^_{|}~"
}

resource "aws_secretsmanager_secret" "auth" {
  name                    = "${var.name}-redis-auth-${var.environment}"
  description             = "ElastiCache Redis auth token for ${var.name} (${var.environment})"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = local.is_prod ? 30 : 7
  tags                    = local.merged_tags
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id     = aws_secretsmanager_secret.auth.id
  secret_string = jsonencode({ auth_token = random_password.auth.result })
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.name}-${var.environment}"
  subnet_ids = var.subnet_ids
  tags       = local.merged_tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-redis-${var.environment}"
  description = "Redis ingress for chrono-synth ${var.name}"
  vpc_id      = var.vpc_id
  tags        = local.merged_tags
}

resource "aws_security_group_rule" "ingress" {
  count                    = length(var.ingress_security_group_ids)
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = var.ingress_security_group_ids[count.index]
  security_group_id        = aws_security_group.this.id
  description              = "Redis from caller-managed security group"
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.name}-${var.environment}"
  description          = "Chrono Synth ${var.name} (${var.environment})"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = local.resolved_node_type
  num_cache_clusters   = local.resolved_num_cache_clusters
  parameter_group_name = "default.redis${split(".", var.engine_version)[0]}"

  port = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.this.id]

  multi_az_enabled           = local.multi_az
  automatic_failover_enabled = local.automatic_failover

  # Encryption + auth — always on.
  at_rest_encryption_enabled = true
  kms_key_id                 = var.kms_key_id
  transit_encryption_enabled = true
  auth_token                 = random_password.auth.result

  snapshot_retention_limit = local.snapshot_retention_days
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "sun:04:00-sun:05:00"

  apply_immediately = !local.is_prod

  tags = local.merged_tags

  # Auth token rotation: AWS supports rotation via `auth_token_update_strategy`
  # but it requires a follow-up apply with new token; we keep the token
  # generated at creation and rotate via Secrets Manager rotation Lambda
  # in a separate PR.
  lifecycle {
    ignore_changes = [auth_token]
  }
}
