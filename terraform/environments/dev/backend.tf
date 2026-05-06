# Remote state backend.
#
# Bucket + DynamoDB table are bootstrapped manually (chicken-and-egg) once
# per AWS account. The bootstrap script lives in
# scripts/terraform-bootstrap.sh (planned).
#
# To migrate state from another backend:
#   terraform init -migrate-state -backend-config=key=dev/terraform.tfstate

terraform {
  backend "s3" {
    bucket         = "chrono-synth-terraform-state-dev"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "chrono-synth-terraform-locks"
    encrypt        = true
  }
}
