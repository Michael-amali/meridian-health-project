# Phase 3: bronze -> silver. Crawls the 7 raw sources into the Glue Catalog,
# then cleanses each one into partitioned Parquet: rows that pass a
# per-source Glue Data Quality ruleset are promoted, rows that don't are
# quarantined instead (see src/glue_jobs/bronze_to_silver/).
#
# Orchestration (running these on a schedule, retries) is Phase 5 - this
# module only builds the crawlers/jobs, run manually for now.

locals {
  source_script_dir = "${path.module}/../../../src/glue_jobs/bronze_to_silver"
  script_s3_prefix  = "glue-jobs/bronze-to-silver"

  # The 5 daily batch CSV sources, with the exact column order each
  # generator writes (see src/generators/batch/*.py's FIELDNAMES). Defined
  # explicitly rather than crawled - see the raw_csv table note below.
  csv_sources = {
    visits = [
      "visit_id", "patient_id", "facility_id", "department", "visit_type",
      "attending_staff_id", "admission_ts", "discharge_ts",
    ]
    staff_schedules = [
      "staff_id", "facility_id", "department", "role", "shift_date",
      "shift_name", "shift_start", "shift_end",
    ]
    billing_claims = [
      "claim_id", "patient_id", "facility_id", "payer", "claim_amount",
      "status", "service_date",
    ]
    pharmacy_inventory = [
      "facility_id", "drug_name", "current_stock", "reorder_threshold",
      "unit_cost", "snapshot_date",
    ]
    bed_capacity = [
      "facility_id", "department", "total_beds", "occupied_beds", "snapshot_date",
    ]
  }

  # The 2 Firehose-delivered streaming domains - crawled rather than defined
  # explicitly, since JSON keys are unambiguous (no header-row problem).
  json_sources = toset(["vitals", "prescriptions"])

  # All 7 sources this phase promotes to cleansed.
  sources = toset(concat(keys(local.csv_sources), tolist(local.json_sources)))
}

# --- Catalog databases - identical shape, so looped (same convention as the
# 5 S3 buckets in s3-data-lake) ---

resource "aws_glue_catalog_database" "this" {
  for_each = toset(["raw", "cleansed"])

  name = "meridian_${each.key}_${var.env}"
}

# --- common.py is shared by every cleansing job script below (schema/DQ
# rules differ per source, the read/gate/write mechanics don't) - uploaded
# once here rather than duplicated per job ---

resource "aws_s3_object" "common_module" {
  bucket = var.scripts_bucket_name
  key    = "${local.script_s3_prefix}/common.py"
  source = "${local.source_script_dir}/common.py"

  # source_hash, not etag - see the same note in modules/glue-job/main.tf.
  source_hash = filemd5("${local.source_script_dir}/common.py")

  tags = var.tags
}

# --- One cleansing job per source ---

module "cleansing_job" {
  source = "../glue-job"

  for_each = local.sources

  job_name          = "meridian-cleanse-${each.key}-${var.env}"
  script_local_path = "${local.source_script_dir}/${each.key}.py"
  script_s3_key     = "${local.script_s3_prefix}/${each.key}.py"
  scripts_bucket    = var.scripts_bucket_name
  role_arn          = var.glue_role_arn

  default_arguments = {
    "--extra-py-files"    = "s3://${aws_s3_object.common_module.bucket}/${aws_s3_object.common_module.key}"
    "--RAW_BUCKET"        = var.raw_bucket_name
    "--CLEANSED_BUCKET"   = var.cleansed_bucket_name
    "--RAW_DATABASE"      = aws_glue_catalog_database.this["raw"].name
    "--CLEANSED_DATABASE" = aws_glue_catalog_database.this["cleansed"].name
    "--SOURCE"            = each.key
  }

  tags = var.tags
}

# --- Raw CSV tables: defined explicitly, not crawled ---
#
# Every column in these 5 sources' CSVs is text, so Glue's crawler can't
# statistically tell the header row apart from a data row (no type change to
# key off) and leaves the columns unclassified as col0/col1/... This
# project's own generators (src/generators/batch/*.py) already define the
# exact column list for each source, so there's nothing to "discover" here -
# a plain Terraform table beats fighting the crawler's guesswork. Partition
# projection (the `projection.*` parameters) tells Athena how to derive a
# source's dt= partitions from the date range itself, so new days are
# queryable immediately without re-crawling or an explicit ADD PARTITION.
resource "aws_glue_catalog_table" "raw_csv" {
  for_each = local.csv_sources

  name          = each.key
  database_name = aws_glue_catalog_database.this["raw"].name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"              = "csv"
    "skip.header.line.count"      = "1"
    "projection.enabled"          = "true"
    "projection.dt.type"          = "date"
    "projection.dt.format"        = "yyyy-MM-dd"
    "projection.dt.range"         = "2025-01-01,NOW"
    "projection.dt.interval"      = "1"
    "projection.dt.interval.unit" = "DAYS"
    "storage.location.template"   = "s3://${var.raw_bucket_name}/${each.key}/dt=$${dt}/"
  }

  partition_keys {
    name = "dt"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${var.raw_bucket_name}/${each.key}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"

      parameters = {
        "field.delim" = ","
      }
    }

    dynamic "columns" {
      for_each = each.value

      content {
        name = columns.value
        type = "string"
      }
    }
  }
}

# --- Crawlers: raw JSON streaming sources, plus the whole cleansed layer
# (+ the DQ results table) ---

module "raw_crawler" {
  source = "../glue-crawler"

  name          = "meridian-raw-crawler-${var.env}"
  database_name = aws_glue_catalog_database.this["raw"].name
  role_arn      = var.glue_role_arn
  s3_targets    = [for source in local.json_sources : "s3://${var.raw_bucket_name}/${source}/"]

  tags = var.tags
}

module "cleansed_crawler" {
  source = "../glue-crawler"

  name          = "meridian-cleansed-crawler-${var.env}"
  database_name = aws_glue_catalog_database.this["cleansed"].name
  role_arn      = var.glue_role_arn
  s3_targets = concat(
    [for source in local.sources : "s3://${var.cleansed_bucket_name}/${source}/"],
    ["s3://${var.cleansed_bucket_name}/_dq_results/"]
  )

  tags = var.tags
}

# Empty placeholder object per source, so _quarantine/<source>/ is visible in
# S3 from the moment this phase is applied - not only after the first bad
# record ever lands there. Purely for discoverability (so anyone looking at
# the bucket knows where quarantined rows will show up); the cleansing jobs
# themselves don't read or depend on this object.
resource "aws_s3_object" "quarantine_placeholder" {
  for_each = local.sources

  bucket = var.cleansed_bucket_name
  key    = "_quarantine/${each.key}/"

  tags = var.tags
}

# Quarantine gets its own crawler rather than joining cleansed_crawler above:
# each source lives at _quarantine/<source>/, and without a table_prefix that
# last path segment (e.g. "bed_capacity") would collide with the real
# cleansed table of the same name. table_prefix makes these
# "quarantine_bed_capacity", "quarantine_visits", etc. instead.
module "quarantine_crawler" {
  source = "../glue-crawler"

  name          = "meridian-quarantine-crawler-${var.env}"
  database_name = aws_glue_catalog_database.this["cleansed"].name
  role_arn      = var.glue_role_arn
  table_prefix  = "quarantine_"
  s3_targets    = [for source in local.sources : "s3://${var.cleansed_bucket_name}/_quarantine/${source}/"]

  tags = var.tags
}

# --- Athena workgroup, so a first query in this account has somewhere to put
# results without relying on account-level default settings ---

resource "aws_athena_workgroup" "analytics" {
  name = "meridian-analytics-${var.env}"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.logs_bucket_name}/athena-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = var.kms_key_arn
      }
    }
  }

  tags = var.tags
}
