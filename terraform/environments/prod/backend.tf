# Remote state for the prod environment. Same state bucket/lock table as
# every other environment, different key so state files never collide.
terraform {
  backend "s3" {
    bucket         = "meridian-terraform-state-myk"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "meridian-terraform-locks"
    encrypt        = true
  }
}
