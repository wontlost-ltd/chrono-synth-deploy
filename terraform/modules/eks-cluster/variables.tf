variable "name" {
  description = "Cluster name. Becomes part of the AWS resource ID."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 lowercase chars, digits, or hyphens."
  }
}

variable "environment" {
  description = "dev / staging / prod. Drives node-group sizing defaults."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "cluster_version" {
  description = "Kubernetes minor version (e.g. 1.32). Pin explicitly — auto-upgrade is OFF."
  type        = string
  default     = "1.32"
}

variable "vpc_id" {
  description = "VPC ID where the cluster lives."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the control plane + worker nodes. At least 2 across different AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnets required for EKS multi-AZ."
  }
}

variable "node_groups" {
  description = "Map of node-group definitions. Each entry overrides the per-env defaults."
  type = map(object({
    instance_types = optional(list(string))
    min_size       = optional(number)
    max_size       = optional(number)
    desired_size   = optional(number)
    capacity_type  = optional(string)  # 'ON_DEMAND' or 'SPOT'
    labels         = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string  # 'NO_SCHEDULE' / 'NO_EXECUTE' / 'PREFER_NO_SCHEDULE'
    })), [])
  }))
  default = {
    workload = {}
  }
}

variable "endpoint_public_access" {
  description = "Whether the EKS API server is reachable from the public internet. OFF by default; enable only with CIDR allowlist."
  type        = bool
  default     = false
}

variable "endpoint_public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Ignored when endpoint_public_access=false."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Resource tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
