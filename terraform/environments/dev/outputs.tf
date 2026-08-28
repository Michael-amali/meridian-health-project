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

output "raw_database_name" {
  description = "Glue Catalog database holding the raw tables."
  value       = module.bronze_to_silver.raw_database_name
}

output "cleansed_database_name" {
  description = "Glue Catalog database holding the cleansed tables (and dq_results)."
  value       = module.bronze_to_silver.cleansed_database_name
}

output "cleansing_job_names" {
  description = "Map of source name to its cleansing Glue job name - useful for manual `aws glue start-job-run` testing."
  value       = module.bronze_to_silver.cleansing_job_names
}

output "raw_crawler_name" {
  description = "Name of the raw-layer crawler."
  value       = module.bronze_to_silver.raw_crawler_name
}

output "cleansed_crawler_name" {
  description = "Name of the cleansed-layer crawler."
  value       = module.bronze_to_silver.cleansed_crawler_name
}

output "quarantine_crawler_name" {
  description = "Name of the quarantine crawler (tables come out named quarantine_<source>)."
  value       = module.bronze_to_silver.quarantine_crawler_name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup to run verification queries in."
  value       = module.bronze_to_silver.athena_workgroup_name
}

output "curated_database_name" {
  description = "Glue Catalog database holding the curated fact/dim tables."
  value       = module.silver_to_gold.curated_database_name
}

output "curated_job_names" {
  description = "Map of table name to its curation Glue job name - useful for manual `aws glue start-job-run` testing."
  value       = module.silver_to_gold.curated_job_names
}

output "curated_crawler_name" {
  description = "Name of the curated-layer crawler."
  value       = module.silver_to_gold.curated_crawler_name
}

output "demo_role_arns" {
  description = "Map of demo persona (analyst/executive) to its IAM role ARN - `aws sts assume-role` into one of these to verify PII column masking."
  value       = module.lake_formation_grants.demo_role_arns
}

output "pipeline_alerts_topic_arn" {
  description = "ARN of the SNS topic pipeline success/failure notifications publish to."
  value       = module.sns_alerts.topic_arn
}

output "batch_daily_state_machine_arn" {
  description = "ARN of the batch-daily Step Functions pipeline - useful for manual `aws stepfunctions start-execution` testing."
  value       = module.batch_daily_pipeline.state_machine_arn
}

output "streaming_curation_state_machine_arn" {
  description = "ARN of the streaming-curation Step Functions pipeline - useful for manual `aws stepfunctions start-execution` testing."
  value       = module.streaming_curation_pipeline.state_machine_arn
}

output "pipeline_dashboard_name" {
  description = "Name of the Phase 5 CloudWatch dashboard."
  value       = module.monitoring.dashboard_name
}

output "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup name - useful for manual `aws redshift-data execute-statement` testing."
  value       = module.redshift_warehouse.workgroup_name
}

output "redshift_database_name" {
  description = "Redshift database name."
  value       = module.redshift_warehouse.database_name
}

output "redshift_admin_secret_arn" {
  description = "Secrets Manager ARN holding the Redshift admin credentials - pass as --secret-arn for manual verification queries via the Data API."
  value       = module.redshift_warehouse.admin_secret_arn
}

output "facility_manager_demo_role_arns" {
  description = "Map of facility (FAC01/FAC02/FAC03) to its demo facility-manager IAM role ARN - `aws sts assume-role` into one, then read its secret (facility_manager_demo_secret_arns) to verify RLS restricts rows to that facility."
  value       = module.redshift_warehouse.facility_manager_demo_role_arns
}

output "facility_manager_demo_secret_arns" {
  description = "Map of facility (FAC01/FAC02/FAC03) to the Secrets Manager ARN holding its demo db_user's password - only the matching facility_manager_demo_role_arns role can read it."
  value       = module.redshift_warehouse.demo_facility_user_secret_arns
}
