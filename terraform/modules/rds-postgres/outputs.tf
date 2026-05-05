output "endpoint" {
  description = "RDS endpoint hostname (without port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "RDS listener port."
  value       = aws_db_instance.this.port
}

output "id" {
  description = "DB instance identifier (AWS resource ID)."
  value       = aws_db_instance.this.id
}

output "security_group_id" {
  description = "Security group attached to the RDS instance — append app-tier ingress here."
  value       = aws_security_group.this.id
}

output "master_secret_arn" {
  description = "Secrets Manager ARN holding the master credentials. Consume via External Secrets Operator from K8s."
  value       = aws_secretsmanager_secret.master.arn
}

output "master_secret_name" {
  description = "Secrets Manager name of the master credentials secret (convenience)."
  value       = aws_secretsmanager_secret.master.name
}
