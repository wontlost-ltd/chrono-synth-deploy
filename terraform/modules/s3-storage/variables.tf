variable "name" {
  description = "Bucket name (must be globally unique). Use chrono-synth-<purpose>-<env> convention."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.name))
    error_message = "S3 bucket names must be 3-63 lowercase chars, digits, dots or hyphens, starting + ending alphanumeric."
  }
}

variable "environment" {
  description = "dev / staging / prod. Drives lifecycle + retention defaults."
  type        = string
}

variable "kms_key_id" {
  description = "KMS key for SSE-KMS at-rest encryption. Required."
  type        = string
}

variable "lifecycle_transition_days" {
  description = "Days before objects move to S3 Standard-IA. Set to 0 to disable."
  type        = number
  default     = 30
}

variable "lifecycle_expiration_days" {
  description = "Days before objects are permanently deleted. Set to 0 to disable (use with care)."
  type        = number
  default     = 365
}

variable "versioning_enabled" {
  description = "Enable bucket versioning. Recommended for portability exports + backups."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Resource tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
