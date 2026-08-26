# Terraform state backend bootstrap

Creates the S3 bucket (`meridian-terraform-state-<account-id>`) and DynamoDB table
(`meridian-terraform-locks`) that every environment under `terraform/environments/`
uses as its remote state backend.

This has already been applied once for this AWS account. You should not need to run
it again unless you are setting this project up in a brand new AWS account.

```bash
cd terraform/bootstrap
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

This config uses **local** state (no backend block) - deliberately, since it creates
the very bucket everything else stores state in. Keep changes here minimal and rare.

The local `terraform.tfstate` this produces (gitignored, never committed) is the only
record Terraform has of these two resources. If you lose it, don't recreate the
bucket/table - `terraform import` them back into a fresh local state instead.
