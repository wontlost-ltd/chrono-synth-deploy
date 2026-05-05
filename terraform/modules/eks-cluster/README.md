# Module: eks-cluster (skeleton)

> Status: **placeholder**. The cluster topology decision (node-group
> shapes, AMI pinning, IRSA setup, Karpenter vs cluster-autoscaler) is
> its own PR. This README captures the contract so callers can plan
> against expected outputs.

## Planned interface

```hcl
module "eks" {
  source = "../../modules/eks-cluster"

  name        = "chrono-synth"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  cluster_version = "1.32"

  # Per-env defaults: dev=t4g.medium x2, staging=r6g.large x3, prod=r6g.xlarge x6
  node_groups = {
    workload = {
      instance_types = ["m6g.large"]
      min_size       = 3
      max_size       = 10
      desired_size   = 3
    }
  }

  tags = local.common_tags
}
```

## Planned outputs

- `cluster_name`
- `cluster_endpoint`
- `cluster_certificate_authority_data`
- `oidc_issuer_url` (for IRSA)
- `kubeconfig` (raw config; sensitive)

## Tracking

Implementation tracked in `enterprise-readiness-2026.md` § P1.1.
Likely to wrap the `terraform-aws-modules/eks/aws` upstream module
rather than reimplement; the `validate` step in the EKS upstream
catches dozens of common misconfigurations we'd otherwise have to
write tests for.
