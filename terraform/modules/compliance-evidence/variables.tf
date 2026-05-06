variable "name" {
  description = "Identifier prefix for the IAM role + S3 bucket reference."
  type        = string
}

variable "environment" {
  description = "dev / staging / prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "evidence_bucket_name" {
  description = "Name of the existing S3 bucket where evidence is uploaded. Provisioned by terraform/modules/s3-storage."
  type        = string
}

variable "evidence_bucket_arn" {
  description = "ARN of the evidence bucket (passed alongside the name to avoid an ARN-construction round trip)."
  type        = string
}

variable "evidence_bucket_kms_key_arn" {
  description = "ARN of the KMS key encrypting the evidence bucket. Used to scope the IAM policy to a specific key (no wildcards)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN. Output from terraform/modules/eks-cluster.oidc_provider_arn."
  type        = string
}

variable "oidc_issuer_url" {
  description = "EKS OIDC issuer URL (without 'https://' prefix). Used in the trust policy condition."
  type        = string
}

variable "k8s_namespace" {
  description = "Kubernetes namespace running the evidence cronjob."
  type        = string
  default     = "compliance"
}

variable "k8s_service_account_name" {
  description = "Service account name the cronjob assumes via IRSA."
  type        = string
  default     = "compliance-evidence"
}

variable "tags" {
  description = "Resource tags merged into the AWS-managed defaults."
  type        = map(string)
  default     = {}
}
