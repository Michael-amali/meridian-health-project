output "bucket_names" {
  description = "Map of layer name (raw/cleansed/curated/scripts/logs) to actual S3 bucket name."
  value       = { for layer, bucket in aws_s3_bucket.this : layer => bucket.bucket }
}

output "bucket_arns" {
  description = "Map of layer name to S3 bucket ARN."
  value       = { for layer, bucket in aws_s3_bucket.this : layer => bucket.arn }
}
