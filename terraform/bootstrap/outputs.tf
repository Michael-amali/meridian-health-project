output "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Used in each environment's backend config."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking. Used in each environment's backend config."
  value       = aws_dynamodb_table.terraform_locks.name
}
