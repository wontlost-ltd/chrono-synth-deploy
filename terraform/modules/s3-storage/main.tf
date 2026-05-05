# S3 storage module — chrono-synth standard bucket.
#
# Hardcoded defaults (no override):
#   - SSE-KMS encryption (no SSE-S3, no plaintext)
#   - public-access-block ALL ON (acl + policy + ignore-public + restrict)
#   - object ownership: BucketOwnerEnforced (ACLs disabled)
#
# Configurable:
#   - lifecycle transition + expiration windows
#   - versioning (default ON; suggested for portability + backups)
#
# What this module deliberately doesn't do:
#  - Replication. Cross-region replication is P3.6 territory.
#  - Object lock / WORM. Use only when compliance demands; heavy
#    operational overhead (objects can't be deleted before lock expiry).

locals {
  default_tags = {
    "ManagedBy"   = "terraform"
    "Module"      = "s3-storage"
    "Environment" = var.environment
    "Service"     = "chrono-synth"
  }
  merged_tags = merge(local.default_tags, var.tags)
}

resource "aws_s3_bucket" "this" {
  bucket = var.name
  tags   = local.merged_tags

  # 终止保护：prod 阻止意外销毁。
  lifecycle {
    prevent_destroy = false  # toggle to true on a per-bucket basis when promoting to prod
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_id
    }
    bucket_key_enabled = true  # Reduces KMS API costs for high-throughput access
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.lifecycle_transition_days > 0 || var.lifecycle_expiration_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "default"
    status = "Enabled"

    filter {
      prefix = ""  # apply to all objects
    }

    dynamic "transition" {
      for_each = var.lifecycle_transition_days > 0 ? [1] : []
      content {
        days          = var.lifecycle_transition_days
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "expiration" {
      for_each = var.lifecycle_expiration_days > 0 ? [1] : []
      content {
        days = var.lifecycle_expiration_days
      }
    }

    # Noncurrent (versioned) objects expire faster than current ones.
    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    # Abort multipart uploads stuck for >7 days.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
