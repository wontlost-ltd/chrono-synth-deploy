# tflint config for chrono-synth-deploy/terraform/.
#
# Plugins are auto-installed on `tflint --init`.
# Defaults align with the AWS rule pack; we add a few project-specific
# checks below.

config {
  # Resolve modules ahead of linting; without this, cross-module rules
  # only see the surface they're called from.
  call_module_type = "all"
  force            = false
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled    = true
  version    = "0.41.0"
  source     = "github.com/terraform-linters/tflint-ruleset-aws"
  deep_check = false
}

# Rules we explicitly DISABLE (with rationale):

# terraform_required_version is checked per-module via versions.tf;
# top-level environments inherit. Disable to avoid duplicate noise.
rule "terraform_required_providers" {
  enabled = true
}

# Allow caller-passed tag map merging; the AWS rule otherwise nags
# about each resource not literally tagging itself.
rule "aws_resource_missing_tags" {
  enabled = false
}
