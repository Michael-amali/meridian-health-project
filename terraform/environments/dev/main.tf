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

# Phase 5: orchestration. Two Step Functions pipelines tie phases 2-4
# together on a schedule instead of everything being run by hand:
#   - batch_daily_pipeline: the 5 daily CSV sources (visits, staff_schedules,
#     billing_claims, pharmacy_inventory, bed_capacity) -> their 7 dependent
#     curated tables, then a catalog refresh so that day's new partitions
#     are queryable in Athena.
#   - streaming_curation_pipeline: the 2 Firehose-delivered sources (vitals,
#     prescriptions) -> fact_vitals_alert, on a much shorter interval. No
#     catalog refresh here - see modules/step-functions-pipeline's comment on
#     crawler_states for why that's safe to skip, and skipping it keeps a
#     crawler from running (and costing money) every 30 minutes all day.
#
# dim_patient/dim_staff (reference data) and dim_date/dim_facility/
# dim_department (static lookups) are deliberately NOT scheduled - none of
# their sources change day to day, so Phase 4's one-time manual run is still
# good; see terraform/modules/silver-to-gold's header comment.

module "sns_alerts" {
  source = "../../modules/sns-alerts"

  env         = var.env
  kms_key_arn = module.kms.key_arn
  alert_email = var.alert_email
}

# Phase 6: warehouse. Redshift Serverless namespace/workgroup, the 13-table
# star schema (dist/sort keys tuned per table), an initial load from the
# curated bucket, and facility-scoped row-level security - see
# modules/redshift-warehouse's header comments for the design reasoning.
# Declared here (ahead of the pipelines below) because both pipelines
# reference its outputs to wire their own ongoing Redshift-load stage.
# Depends on silver_to_gold directly (not just the curated bucket) because
# the initial COPY load needs actual curated Parquet to already exist.

module "redshift_warehouse" {
  source = "../../modules/redshift-warehouse"

  env                 = var.env
  curated_bucket_name = module.s3_data_lake.bucket_names["curated"]
  curated_bucket_arn  = module.s3_data_lake.bucket_arns["curated"]
  kms_key_arn         = module.kms.key_arn

  depends_on = [module.silver_to_gold]
}

module "batch_daily_pipeline" {
  source = "../../modules/step-functions-pipeline"

  env  = var.env
  name = "batch-daily"

  cleanse_job_names = [
    for source in ["visits", "staff_schedules", "billing_claims", "pharmacy_inventory", "bed_capacity"] :
    module.bronze_to_silver.cleansing_job_names[source]
  ]
  curate_job_names = [
    for table in ["fact_patient_visit", "fact_bed_occupancy", "fact_staffing", "fact_claim", "fact_pharmacy_inventory", "dim_payer", "dim_drug"] :
    module.silver_to_gold.curated_job_names[table]
  ]
  crawler_names = [
    module.bronze_to_silver.cleansed_crawler_name,
    module.bronze_to_silver.quarantine_crawler_name,
  ]

  sns_topic_arn = module.sns_alerts.topic_arn
  kms_key_arn   = module.kms.key_arn
  # 08:00 UTC - comfortably after the batch generators finish (06:00-06:20
  # UTC, see modules/batch-generators). Each cleansing job defaults to
  # processing *yesterday's* partition (see resolved_args() in
  # src/glue_jobs/bronze_to_silver/common.py), so this always has a full,
  # fully-landed day of data to work with regardless of exactly when it runs.
  schedule_expression = "cron(0 8 * * ? *)"

  # Phase 6: keep these 7 curated tables fresh in Redshift right after
  # they're curated, instead of only loading them once at `terraform apply`
  # time (see modules/redshift-warehouse's initial_load resource for that
  # one-time load).
  redshift_tables_to_load = [
    "fact_patient_visit", "fact_bed_occupancy", "fact_staffing",
    "fact_claim", "fact_pharmacy_inventory", "dim_payer", "dim_drug",
  ]
  redshift_workgroup_name   = module.redshift_warehouse.workgroup_name
  redshift_workgroup_arn    = module.redshift_warehouse.workgroup_arn
  redshift_database_name    = module.redshift_warehouse.database_name
  redshift_admin_secret_arn = module.redshift_warehouse.admin_secret_arn
  curated_bucket_name       = module.s3_data_lake.bucket_names["curated"]
  redshift_service_role_arn = module.redshift_warehouse.redshift_service_role_arn
}

module "streaming_curation_pipeline" {
  source = "../../modules/step-functions-pipeline"

  env  = var.env
  name = "streaming-curation"

  cleanse_job_names = [
    module.bronze_to_silver.cleansing_job_names["vitals"],
    module.bronze_to_silver.cleansing_job_names["prescriptions"],
  ]
  curate_job_names = [
    module.silver_to_gold.curated_job_names["fact_vitals_alert"],
  ]

  sns_topic_arn       = module.sns_alerts.topic_arn
  kms_key_arn         = module.kms.key_arn
  schedule_expression = "rate(30 minutes)"

  # Phase 6: this pipeline only curates fact_vitals_alert, so it only loads
  # that one table.
  redshift_tables_to_load   = ["fact_vitals_alert"]
  redshift_workgroup_name   = module.redshift_warehouse.workgroup_name
  redshift_workgroup_arn    = module.redshift_warehouse.workgroup_arn
  redshift_database_name    = module.redshift_warehouse.database_name
  redshift_admin_secret_arn = module.redshift_warehouse.admin_secret_arn
  curated_bucket_name       = module.s3_data_lake.bucket_names["curated"]
  redshift_service_role_arn = module.redshift_warehouse.redshift_service_role_arn
}

module "monitoring" {
  source = "../../modules/monitoring"

  env           = var.env
  sns_topic_arn = module.sns_alerts.topic_arn

  state_machine_arns = {
    batch-daily        = module.batch_daily_pipeline.state_machine_arn
    streaming-curation = module.streaming_curation_pipeline.state_machine_arn
  }
  kinesis_stream_names = module.kinesis_streaming.stream_names
}
