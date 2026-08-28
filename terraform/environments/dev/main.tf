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

# Phase 3: bronze -> silver. Crawls raw into the Glue Catalog, cleanses each
# source into partitioned Parquet, and gates that promotion on a Glue Data
# Quality ruleset per source.

module "bronze_to_silver" {
  source = "../../modules/bronze-to-silver"

  env                  = var.env
  raw_bucket_name      = module.s3_data_lake.bucket_names["raw"]
  cleansed_bucket_name = module.s3_data_lake.bucket_names["cleansed"]
  scripts_bucket_name  = module.s3_data_lake.bucket_names["scripts"]
  logs_bucket_name     = module.s3_data_lake.bucket_names["logs"]
  kms_key_arn          = module.kms.key_arn
  glue_role_arn        = module.iam_baseline.glue_service_role_arn
}

# Phase 4: silver -> gold + Lake Formation governance. Split into 3 modules
# because of a real ordering constraint (see lake-formation-bootstrap's
# header comment for the full explanation):
#   1. lake_formation_bootstrap - account settings + curated location
#      registration. No dependency on silver_to_gold, applied first.
#   2. silver_to_gold - the curated database/tables/jobs. Must come AFTER
#      bootstrap's account settings land, or the curated database would be
#      created with the legacy default permission grant already attached.
#   3. lake_formation_grants - the actual SELECT/column-exclusion grants.
#      Needs the curated database/tables to exist first, so it comes last.

module "lake_formation_bootstrap" {
  source = "../../modules/lake-formation-bootstrap"

  env                = var.env
  curated_bucket_arn = module.s3_data_lake.bucket_arns["curated"]
  kms_key_arn        = module.kms.key_arn
}

module "silver_to_gold" {
  source = "../../modules/silver-to-gold"

  env                  = var.env
  cleansed_bucket_name = module.s3_data_lake.bucket_names["cleansed"]
  curated_bucket_name  = module.s3_data_lake.bucket_names["curated"]
  scripts_bucket_name  = module.s3_data_lake.bucket_names["scripts"]
  glue_role_arn        = module.iam_baseline.glue_service_role_arn

  depends_on = [module.lake_formation_bootstrap]
}

module "lake_formation_grants" {
  source = "../../modules/lake-formation-grants"

  env                   = var.env
  glue_service_role_arn = module.iam_baseline.glue_service_role_arn
  curated_database_name = module.silver_to_gold.curated_database_name
  curated_resource_arn  = module.lake_formation_bootstrap.curated_resource_arn
  curated_table_names   = module.silver_to_gold.curated_table_names
  pii_table_names       = module.silver_to_gold.pii_table_names
  logs_bucket_arn       = module.s3_data_lake.bucket_arns["logs"]
  kms_key_arn           = module.kms.key_arn
}
