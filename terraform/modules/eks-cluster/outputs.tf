output "cluster_name" {
  description = "Cluster name (also the AWS resource ID)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "K8s API endpoint URL."
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA cert; needed for kubeconfig."
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA."
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN. Use for IRSA trust policies on caller-managed IAM roles."
  value       = module.eks.oidc_provider_arn
}

output "cluster_primary_security_group_id" {
  description = "Cluster's primary security group; appendable for cross-tier ingress."
  value       = module.eks.cluster_primary_security_group_id
}

output "node_security_group_id" {
  description = "Security group attached to the managed node groups; use for app-tier → DB rules."
  value       = module.eks.node_security_group_id
}

output "kms_key_arn" {
  description = "ARN of the cluster's secret-encryption KMS key (per-cluster, separate from app-data CMKs)."
  value       = aws_kms_key.eks.arn
}
