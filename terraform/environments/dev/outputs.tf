output "cluster_name" {
  description = "EKS cluster name (also the AWS resource ID)."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "K8s API endpoint URL."
  value       = module.eks.cluster_endpoint
}

output "rds_endpoint" {
  description = "RDS endpoint hostname."
  value       = module.rds.endpoint
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint hostname."
  value       = module.redis.primary_endpoint
}

output "kms_app_data_key_arn" {
  description = "KMS key ARN protecting RDS + Redis + S3 buckets."
  value       = module.kms_app_data.key_arn
}

output "portability_bucket" {
  description = "S3 bucket for portability exports."
  value       = module.s3_portability.bucket_name
}

output "compliance_evidence_bucket" {
  description = "S3 bucket for weekly compliance evidence uploads."
  value       = module.s3_compliance_evidence.bucket_name
}

output "compliance_evidence_role_arn" {
  description = "IRSA role ARN to annotate on the compliance-evidence ServiceAccount."
  value       = module.compliance_evidence.role_arn
}

output "compliance_evidence_configmap_yaml" {
  description = "ConfigMap YAML for the cronjob; apply with: terraform output -raw compliance_evidence_configmap_yaml | kubectl apply -f -"
  value       = module.compliance_evidence.configmap_yaml
}
