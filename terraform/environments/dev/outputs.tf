output "bucket_names" {
  description = "Map of layer name to S3 bucket name."
  value       = module.s3_data_lake.bucket_names
}

output "kms_key_arn" {
  description = "ARN of the data lake KMS key."
  value       = module.kms.key_arn
}

output "glue_service_role_arn" {
  description = "ARN of the Glue service role."
  value       = module.iam_baseline.glue_service_role_arn
}

output "lambda_generator_role_arn" {
  description = "ARN of the Lambda generator role."
  value       = module.iam_baseline.lambda_generator_role_arn
}
