output "primary_endpoint" {
  description = "Redis primary endpoint hostname (use for read+write)."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Redis reader endpoint hostname (multi-AZ only). Empty string when num_cache_clusters=1."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Redis listener port (always 6379)."
  value       = aws_elasticache_replication_group.this.port
}

output "security_group_id" {
  description = "Security group attached to the replication group — append app-tier ingress here."
  value       = aws_security_group.this.id
}

output "auth_secret_arn" {
  description = "Secrets Manager ARN holding the auth token. Consume via External Secrets Operator from K8s."
  value       = aws_secretsmanager_secret.auth.arn
}

output "auth_secret_name" {
  description = "Secrets Manager name of the auth token secret (convenience)."
  value       = aws_secretsmanager_secret.auth.name
}
