# One-time bootstrap: creates the S3 bucket and DynamoDB table that the rest of
# this project uses as its remote Terraform state backend.
#
# This config intentionally uses LOCAL state (no backend block). You can't store
# state for the bucket that stores state - so this one small config is the
# exception. Run it once per AWS account, then never touch it again unless the
# state backend itself needs to change.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Bucket names must be globally unique across all of AWS, so we suffix with the
# account ID rather than inventing a random name.
locals {
  state_bucket_name = "meridian-terraform-state-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  # Safety net: `terraform destroy` on this config should never silently wipe
  # out every environment's state file.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Project   = "meridian-analytics-platform"
    ManagedBy = "terraform"
    Purpose   = "terraform-remote-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Locking table: prevents two people (or two CI runs) from applying to the same
# environment's state at the same time. On-demand billing since locks are tiny
# and infrequent - no capacity to plan for.
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "meridian-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project   = "meridian-analytics-platform"
    ManagedBy = "terraform"
    Purpose   = "terraform-state-locking"
  }
}
