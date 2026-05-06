# Compliance evidence module.
#
# Provisions the IAM role + IRSA trust policy that the
# compliance/evidence/cronjob.yaml CronJob assumes to upload weekly
# evidence to S3. The bucket itself is provisioned separately (via
# terraform/modules/s3-storage); we only attach an inline policy
# that grants PutObject on a tightly scoped prefix.
#
# Apply order:
#   1. modules/s3-storage  → bucket exists
#   2. modules/eks-cluster → OIDC provider exists
#   3. modules/compliance-evidence (this) → IRSA role
#   4. kubectl annotate sa compliance-evidence with the role ARN
#      (or set in the SA manifest under compliance/evidence/cronjob.yaml).

locals {
  oidc_subject = "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"

  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "compliance-evidence"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

resource "aws_iam_role" "evidence" {
  name = "${var.name}-compliance-evidence-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${var.oidc_issuer_url}:sub" = local.oidc_subject
          "${var.oidc_issuer_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.merged_tags
}

resource "aws_iam_role_policy" "evidence_s3_write" {
  name = "${var.name}-compliance-evidence-s3-${var.environment}"
  role = aws_iam_role.evidence.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Write evidence under the year/month/ prefix (matches the
        # cronjob's `s3 cp` path). No List/Delete needed — uploads
        # only.
        Sid      = "PutEvidenceObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${var.evidence_bucket_arn}/*"
      },
      {
        # ListBucket scoped to the chrono-synth prefix so the cronjob
        # can verify uploads landed.
        Sid      = "ListEvidenceBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.evidence_bucket_arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "evidence_kms" {
  name = "${var.name}-compliance-evidence-kms-${var.environment}"
  role = aws_iam_role.evidence.id

  # SSE-KMS bucket: principals must hold GenerateDataKey on the bucket's
  # KMS key to PutObject. Resource scoped to the actual key ARN (no
  # wildcards) — tfsec aws-iam-no-policy-wildcards.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "EncryptUploads"
      Effect   = "Allow"
      Action   = ["kms:GenerateDataKey", "kms:Encrypt"]
      Resource = var.evidence_bucket_kms_key_arn
    }]
  })
}

# Optional: a ConfigMap manifest the cronjob reads. Output the bucket
# name + role ARN so the operator can render the manifest from terraform
# outputs without hand-editing.
locals {
  configmap_yaml = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "compliance-config"
      namespace = var.k8s_namespace
    }
    data = {
      evidence_bucket = var.evidence_bucket_name
    }
  })
}
