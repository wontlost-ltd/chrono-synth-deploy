output "bucket_name" {
  description = "Bucket name (also globally unique)."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Bucket ARN for IAM policies."
  value       = aws_s3_bucket.this.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name (use for VPC endpoints + CloudFront)."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}
