output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR. Useful for security-group ingress rules from in-VPC sources."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs — for LBs only."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs — for workloads, RDS, ElastiCache."
  value       = module.vpc.private_subnets
}

output "azs" {
  description = "Availability zones the VPC spans."
  value       = module.vpc.azs
}

output "default_security_group_id" {
  description = "Default SG. Don't use for app workloads — pass explicit SGs to other modules."
  value       = module.vpc.default_security_group_id
}
