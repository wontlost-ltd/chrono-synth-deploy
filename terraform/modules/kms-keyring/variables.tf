variable "name" {
  description = "Identifier prefix for the KMS key alias and resource tags."
  type        = string

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 64
    error_message = "name must be 3-64 characters."
  }
}

variable "environment" {
  description = "dev / staging / prod. Drives deletion window default."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "service_principal_arns" {
  description = "IAM principal ARNs allowed to use the key for encrypt / decrypt / data-key generation. Must be empty or a list of valid ARNs."
  type        = list(string)
  default     = []
}

variable "deletion_window_in_days" {
  description = "Pending deletion window. Defaults: 30 for prod, 7 for dev/staging. Override only with reason."
  type        = number
  default     = null

  validation {
    condition     = var.deletion_window_in_days == null || (var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30)
    error_message = "deletion_window_in_days must be between 7 and 30 when set."
  }
}

variable "tags" {
  description = "Tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
