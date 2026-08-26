# Remote state for the dev environment. The bucket/table here were created
# once by terraform/bootstrap - see that directory's README before changing
# this file.
terraform {
  backend "s3" {
    bucket         = "meridian-terraform-state-myk"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "meridian-terraform-locks"
    encrypt        = true
  }
}
