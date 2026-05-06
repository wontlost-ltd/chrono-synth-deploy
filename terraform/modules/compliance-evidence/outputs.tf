output "role_arn" {
  description = "ARN of the IAM role the compliance-evidence ServiceAccount assumes via IRSA."
  value       = aws_iam_role.evidence.arn
}

output "role_name" {
  description = "IAM role name (convenience)."
  value       = aws_iam_role.evidence.name
}

output "configmap_yaml" {
  description = "Rendered ConfigMap YAML the cronjob reads. Apply with: terraform output -raw configmap_yaml | kubectl apply -f -"
  value       = local.configmap_yaml
}

output "service_account_annotation" {
  description = "Annotation to attach to the ServiceAccount: eks.amazonaws.com/role-arn=<this>"
  value       = aws_iam_role.evidence.arn
}
