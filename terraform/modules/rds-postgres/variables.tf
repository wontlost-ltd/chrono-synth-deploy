variable "name" {
  description = "Identifier prefix for the RDS cluster + DB. Becomes part of the AWS resource ID; keep ≤63 chars total."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 40
    error_message = "name must be 3-40 characters (leaves room for AWS-side suffixes)."
  }
}

variable "environment" {
  description = "dev / staging / prod. Drives default sizing + retention windows."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "engine_version" {
  description = "Postgres major.minor (e.g. 17.2). Pin explicitly — auto-upgrade is OFF for prod."
  type        = string
  default     = "17.2"
}

variable "instance_class" {
  description = "RDS instance class. Defaults follow the env convention; override for tenant-class workloads."
  type        = string
  default     = null
}

variable "allocated_storage_gb" {
  description = "Initial GP3 storage in GB. Auto-scales up to max_allocated_storage_gb."
  type        = number
  default     = 100

  validation {
    condition     = var.allocated_storage_gb >= 20 && var.allocated_storage_gb <= 16384
    error_message = "allocated_storage_gb must be between 20 and 16384."
  }
}

variable "max_allocated_storage_gb" {
  description = "Upper bound for storage auto-scaling. Set to allocated_storage_gb for a fixed allocation."
  type        = number
  default     = 1000
}

variable "vpc_id" {
  description = "VPC the subnet group + security group attach to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs — at least 2 across different AZs for multi-AZ deployment."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets required for RDS multi-AZ."
  }
}

variable "kms_key_id" {
  description = "KMS key for storage + automated backup encryption. Required (no plaintext)."
  type        = string
}

variable "ingress_security_group_ids" {
  description = "Security group IDs allowed to connect on port 5432."
  type        = list(string)
}

variable "tags" {
  description = "Resource tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
