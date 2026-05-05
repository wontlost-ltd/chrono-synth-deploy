# Module: elasticache-redis (skeleton)

> Status: **placeholder**. Body lands alongside the EKS module.

## Planned interface

```hcl
module "redis" {
  source = "../../modules/elasticache-redis"

  name           = "chrono-synth"
  environment    = "prod"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  kms_key_id     = module.kms.key_arn
  engine_version = "8.0"

  # Per-env defaults: dev=cache.t4g.small x1, prod=cache.r7g.large x2 (Sentinel)
  num_cache_nodes = 1
  node_type       = null  # auto-select per env

  ingress_security_group_ids = [module.eks.cluster_primary_security_group_id]

  tags = local.common_tags
}
```

## Planned outputs

- `endpoint` (primary endpoint hostname)
- `port` (always 6379)
- `security_group_id`

## Notes

- Encryption-at-rest + in-transit (TLS) ON by default.
- Auth token via Secrets Manager; rotation via Lambda.
- Multi-AZ replication group for staging + prod (single-AZ fine for dev).
