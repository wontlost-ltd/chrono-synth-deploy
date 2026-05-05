# RDS PostgreSQL module — chrono-synth standard postgres instance.
#
# Defaults follow the per-environment convention:
#   dev      → db.t4g.medium, single-AZ, 7-day backup
#   staging  → db.r6g.large,  multi-AZ,  14-day backup
#   prod     → db.r6g.xlarge, multi-AZ,  35-day backup
#
# Caller can override any of these via the explicit variables. PII /
# regulated workloads should always run on multi-AZ regardless of env.
#
# What this module deliberately doesn't do:
#  - Manage replicas. Cross-region replicas are P3.6 territory.
#  - Manage parameter groups. Engine-version-specific parameter
#    groups are env-specific; pass an existing group via
#    aws_db_instance.parameter_group_name in a per-env override
#    if needed.
#  - Manage credentials. The module creates a master password
#    via Secrets Manager but does NOT rotate it; rotation is
#    a Lambda + RDS proxy concern, separate PR.

locals {
  is_prod              = var.environment == "prod"
  is_staging           = var.environment == "staging"
  default_instance_class = (
    local.is_prod ? "db.r6g.xlarge"
    : local.is_staging ? "db.r6g.large"
    : "db.t4g.medium"
  )
  resolved_instance_class = coalesce(var.instance_class, local.default_instance_class)

  backup_retention_days = (
    local.is_prod ? 35
    : local.is_staging ? 14
    : 7
  )

  # 多 AZ 仅 staging + prod 启用；dev 单 AZ 节省成本
  multi_az = local.is_prod || local.is_staging

  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "rds-postgres"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

resource "random_password" "master" {
  length  = 32
  special = true
  # RDS rejects: / @ " (space)
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "${var.name}-rds-master-${var.environment}"
  description             = "RDS master password for ${var.name} (${var.environment})"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = local.is_prod ? 30 : 7
  tags                    = local.merged_tags
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    username = "chrono_admin"
    password = random_password.master.result
  })
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-${var.environment}"
  subnet_ids = var.subnet_ids
  tags       = local.merged_tags
}

resource "aws_security_group" "this" {
  name        = "${var.name}-rds-${var.environment}"
  description = "Postgres ingress for chrono-synth ${var.name}"
  vpc_id      = var.vpc_id
  tags        = local.merged_tags
}

resource "aws_security_group_rule" "ingress" {
  count                    = length(var.ingress_security_group_ids)
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.ingress_security_group_ids[count.index]
  security_group_id        = aws_security_group.this.id
  description              = "Postgres from caller-managed security group"
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name}-${var.environment}"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = local.resolved_instance_class

  username = "chrono_admin"
  password = random_password.master.result

  allocated_storage     = var.allocated_storage_gb
  max_allocated_storage = var.max_allocated_storage_gb
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_id

  vpc_security_group_ids = [aws_security_group.this.id]
  db_subnet_group_name   = aws_db_subnet_group.this.name
  publicly_accessible    = false

  multi_az = local.multi_az

  backup_retention_period = local.backup_retention_days
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot   = true

  # Auto-minor upgrades: ON for dev/staging, OFF for prod (manual maintenance window).
  auto_minor_version_upgrade = !local.is_prod

  # 删除保护 + 终端快照只在 prod 启用；dev/staging 允许快速重建。
  deletion_protection      = local.is_prod
  skip_final_snapshot      = !local.is_prod
  final_snapshot_identifier = local.is_prod ? "${var.name}-${var.environment}-final" : null

  # Enhanced monitoring + Performance Insights for staging/prod.
  monitoring_interval                   = local.is_prod ? 30 : (local.is_staging ? 60 : 0)
  monitoring_role_arn                   = local.is_prod || local.is_staging ? aws_iam_role.monitoring[0].arn : null
  performance_insights_enabled          = local.is_prod || local.is_staging
  performance_insights_retention_period = local.is_prod ? 731 : 7

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = local.merged_tags
}

# Enhanced monitoring role (only created for staging/prod).
resource "aws_iam_role" "monitoring" {
  count = local.is_prod || local.is_staging ? 1 : 0
  name  = "${var.name}-rds-monitoring-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.merged_tags
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count      = local.is_prod || local.is_staging ? 1 : 0
  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
