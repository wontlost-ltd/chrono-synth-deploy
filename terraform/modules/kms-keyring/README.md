# Module: kms-keyring (skeleton)

> Status: **placeholder**. Body lands first (other modules need a
> KMS key as input).

## Planned interface

```hcl
module "kms" {
  source = "../../modules/kms-keyring"

  name        = "chrono-synth"
  environment = "prod"

  # Application principals allowed to encrypt/decrypt via this key.
  # Typically the EKS service account ARN list via IRSA.
  service_principal_arns = [
    module.eks.kms_user_role_arn,
  ]

  tags = local.common_tags
}
```

## Planned outputs

- `key_id`
- `key_arn`
- `alias_arn`

## Notes

- `enable_key_rotation = true` (annual auto-rotation).
- `deletion_window_in_days = 30` (prod) / `7` (dev/staging) — gives
  ops time to revoke a wrong-key delete.
- Key policy grants:
  - root account: full management.
  - service principals: kms:Encrypt / Decrypt / ReEncrypt /
    GenerateDataKey / DescribeKey only — no admin operations.
- One key per environment; do **not** share KMS keys across env
  boundaries (defeats crypto-shred per ADR 0004).
