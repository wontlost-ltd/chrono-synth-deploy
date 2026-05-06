variable "name" {
  description = "Identifier prefix for the VPC + child resources."
  type        = string
}

variable "environment" {
  description = "dev / staging / prod. Drives single-NAT (dev) vs HA-NAT (staging+prod)."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "cidr_block" {
  description = "VPC CIDR. /16 default leaves room for ~64k addresses across 3 AZs."
  type        = string
  default     = "10.20.0.0/16"
}

variable "azs" {
  description = "Availability zones to span. 3 by default; cluster sizing assumes 3-AZ."
  type        = list(string)
}

variable "tags" {
  description = "Resource tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
