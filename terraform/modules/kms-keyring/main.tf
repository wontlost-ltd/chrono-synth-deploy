# KMS keyring — single CMK per (service, environment).
#
# Rotation is annual + automatic. The key policy grants:
#   - root account: full kms:* (so AWS Organizations / IAM admins
#     can lift the key out from under us in an emergency).
#   - service principals (passed via var.service_principal_arns):
#     kms:Encrypt, kms:Decrypt, kms:ReEncrypt*, kms:GenerateDataKey*,
#     kms:DescribeKey only — explicitly NO kms:ScheduleKeyDeletion or
#     other admin operations.
#
# Why one key per (service, env) and not one per resource:
#   - Crypto-shred per ADR 0004 works at the env boundary; sharing a
#     key across envs would defeat per-env data destruction.
#   - One-key-per-resource grows policy surface unboundedly.
#   - Bucket-key on S3 + AWS-managed DEKs on RDS amortize the
#     KMS-API cost; sharing the CMK across resources is fine.

locals {
  is_prod = var.environment == "prod"
  resolved_deletion_window = coalesce(
    var.deletion_window_in_days,
    local.is_prod ? 30 : 7,
  )

  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "kms-keyring"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  description = "Chrono Synth ${var.name} CMK (${var.environment})"

  enable_key_rotation     = true
  deletion_window_in_days = local.resolved_deletion_window
  multi_region            = false

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        # Root account holds the master key bag — needed for AWS
        # account-level recovery and IAM-policy-based delegation.
        {
          Sid    = "EnableRootAdmin"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          }
          Action   = "kms:*"
          Resource = "*"
        },
      ],
      length(var.service_principal_arns) > 0 ? [
        # Service principals get crypto operations only.
        {
          Sid    = "AllowServicePrincipalCrypto"
          Effect = "Allow"
          Principal = {
            AWS = var.service_principal_arns
          }
          Action = [
            "kms:Encrypt",
            "kms:Decrypt",
            "kms:ReEncrypt*",
            "kms:GenerateDataKey",
            "kms:GenerateDataKeyWithoutPlaintext",
            "kms:DescribeKey",
          ]
          Resource = "*"
        },
      ] : [],
    )
  })

  tags = local.merged_tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/chrono-synth-${var.name}-${var.environment}"
  target_key_id = aws_kms_key.this.key_id
}
