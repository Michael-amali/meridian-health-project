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

output "lambda_alerting_role_arn" {
  description = "ARN of the Lambda alerting role."
  value       = module.iam_baseline.lambda_alerting_role_arn
}

output "stream_names" {
  description = "Map of stream key (vitals/prescriptions) to Kinesis stream name."
  value       = module.kinesis_streaming.stream_names
}

output "active_alerts_table_name" {
  description = "Name of the active-alerts DynamoDB table."
  value       = module.dynamodb_alerts.table_name
}

output "batch_generator_function_names" {
  description = "Map of source name to Lambda function name - useful for manual `aws lambda invoke` testing."
  value       = module.batch_generators.function_names
}

output "streaming_producer_function_name" {
  description = "Name of the streaming producer Lambda."
  value       = module.streaming_producer.function_name
}

output "stream_alerting_function_name" {
  description = "Name of the vitals stream alerting Lambda."
  value       = module.streaming_alerts.function_name
}
