# Phase 1 (Foundations): the KMS key, data lake buckets, and baseline service
# roles that every later phase builds on top of. Nothing here processes data
# yet - it just creates a safe, governed place for data to land.

module "kms" {
  source = "../../modules/kms"

  env = var.env
}

module "s3_data_lake" {
  source = "../../modules/s3-data-lake"

  env         = var.env
  kms_key_arn = module.kms.key_arn
}

module "kinesis_streaming" {
  source = "../../modules/kinesis-streaming"

  env             = var.env
  raw_bucket_name = module.s3_data_lake.bucket_names["raw"]
  raw_bucket_arn  = module.s3_data_lake.bucket_arns["raw"]
  kms_key_arn     = module.kms.key_arn
}

module "dynamodb_alerts" {
  source = "../../modules/dynamodb-alerts"

  env = var.env
}

module "iam_baseline" {
  source = "../../modules/iam-baseline"

  env               = var.env
  bucket_arns       = module.s3_data_lake.bucket_arns
  kms_key_arn       = module.kms.key_arn
  stream_arns       = module.kinesis_streaming.stream_arns
  vitals_stream_arn = module.kinesis_streaming.vitals_stream_arn
  alerts_table_arn  = module.dynamodb_alerts.table_arn
}

# Phase 2: synthetic data generators + raw ingestion. Nothing here transforms
# data yet - it only lands it in the raw bucket (Phase 3 owns cleansing).

module "batch_generators" {
  source = "../../modules/batch-generators"

  env             = var.env
  raw_bucket_name = module.s3_data_lake.bucket_names["raw"]
  lambda_role_arn = module.iam_baseline.lambda_generator_role_arn
}

module "streaming_producer" {
  source = "../../modules/streaming-producer"

  env                       = var.env
  vitals_stream_name        = module.kinesis_streaming.stream_names["vitals"]
  prescriptions_stream_name = module.kinesis_streaming.stream_names["prescriptions"]
  lambda_role_arn           = module.iam_baseline.lambda_generator_role_arn
}

module "streaming_alerts" {
  source = "../../modules/streaming-alerts"

  env               = var.env
  vitals_stream_arn = module.kinesis_streaming.vitals_stream_arn
  alerts_table_name = module.dynamodb_alerts.table_name
  lambda_role_arn   = module.iam_baseline.lambda_alerting_role_arn
}
