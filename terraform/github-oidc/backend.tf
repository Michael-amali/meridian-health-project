# Remote state for the CI/CD identity setup. Same state bucket and lock table
# as the environments, its own key - this config is account-global (there is
# one OIDC provider per AWS account), so it deliberately does NOT live inside
# dev/, test/ or prod/. If it did, destroying that environment would take the
# CI roles with it and lock GitHub Actions out of the other two.
terraform {
  backend "s3" {
    bucket         = "meridian-terraform-state-myk"
    key            = "github-oidc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "meridian-terraform-locks"
    encrypt        = true
  }
}
