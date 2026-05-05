output "key_id" {
  description = "KMS key ID (UUID-like). Pass to other modules via kms_key_id input."
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "KMS key ARN. Use for IAM resource constraints."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "Human-readable alias for the key."
  value       = aws_kms_alias.this.name
}

output "alias_arn" {
  description = "ARN of the alias (for cross-account references)."
  value       = aws_kms_alias.this.arn
}
