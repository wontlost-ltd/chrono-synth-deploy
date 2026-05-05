variable "name" {
  description = "Identifier prefix for the replication group + parameter group."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 lowercase chars, digits, or hyphens."
  }
}

variable "environment" {
  description = "dev / staging / prod. Drives multi-AZ + node type defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_id" {
  description = "VPC the security group attaches to."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs — at least 2 across different AZs for staging/prod."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "At least 1 subnet required."
  }
}

variable "kms_key_id" {
  description = "KMS key for at-rest encryption. Required."
  type        = string
}

variable "engine_version" {
  description = "Redis engine version (e.g. 7.1 or 8.0). Pin explicitly."
  type        = string
  default     = "7.1"
}

variable "node_type" {
  description = "ElastiCache node type. Defaults follow the env convention; override for tenant-class workloads."
  type        = string
  default     = null
}

variable "num_cache_clusters" {
  description = "Number of cache clusters in the replication group. 1 for dev (no replication), 2+ for staging/prod (one primary + N replicas)."
  type        = number
  default     = null
}

variable "ingress_security_group_ids" {
  description = "Security group IDs allowed to connect on port 6379."
  type        = list(string)
}

variable "tags" {
  description = "Resource tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
