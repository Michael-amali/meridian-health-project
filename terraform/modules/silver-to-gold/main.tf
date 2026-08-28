# Phase 4: silver -> gold. Curates the 7 cleansed daily sources plus the 2
# Phase 4 reference sources (patients, staff - see modules/bronze-to-silver)
# into a star schema: 7 dimensions + 6 facts (src/glue_jobs/silver_to_gold/).
# Every table is a full-refresh overwrite each run - no SCD history, no
# partitioning - this project's data volumes don't need either.
#
# dim_patient/dim_staff are Terraform-defined tables (not crawled) so their
# PII columns can carry an explicit classification=pii tag - see
# terraform/modules/lake-formation-grants, which keys its column-exclusion
# grants off those same column names.
#
# Orchestration (running these on a schedule) is Phase 5 - this module only
# builds the jobs/crawler, run manually for now.

locals {
  source_script_dir = "${path.module}/../../../src/glue_jobs/silver_to_gold"
  script_s3_prefix  = "glue-jobs/silver-to-gold"

  # Curated table -> the one cleansed source it reads. Omitted for the 3
  # tables with no cleansed input (dim_date is generated, dim_facility/
  # dim_department are hardcoded lookups - see their scripts for why).
  curated_sources = {
    dim_patient             = "patients"
    dim_staff               = "staff"
    dim_payer               = "billing_claims"
    dim_drug                = "pharmacy_inventory"
    fact_patient_visit      = "visits"
    fact_bed_occupancy      = "bed_capacity"
    fact_staffing           = "staff_schedules"
    fact_claim              = "billing_claims"
    fact_pharmacy_inventory = "pharmacy_inventory"
    fact_vitals_alert       = "vitals"
  }

  curated_tables = toset(concat(keys(local.curated_sources), ["dim_date", "dim_facility", "dim_department"]))

  # dim_patient/dim_staff are Terraform-defined below (for PII column
  # tagging), so the crawler only needs to cover the other 11.
  pii_tables     = toset(["dim_patient", "dim_staff"])
  crawled_tables = setsubtract(local.curated_tables, local.pii_tables)

  pii_columns = ["full_name", "date_of_birth", "phone", "government_id"]

  # Terraform-defined PII dims: each one's non-PII key column + type.
  pii_dim_key_columns = {
    dim_patient = "patient_id"
    dim_staff   = "staff_id"
  }
}

resource "aws_glue_catalog_database" "this" {
  for_each = toset(["curated"])

  name = "meridian_${each.key}_${var.env}"
}

# --- common.py is shared by every curation job script below ---

resource "aws_s3_object" "common_module" {
  bucket = var.scripts_bucket_name
  key    = "${local.script_s3_prefix}/common.py"
  source = "${local.source_script_dir}/common.py"

  # source_hash, not etag - see the same note in modules/glue-job/main.tf.
  source_hash = filemd5("${local.source_script_dir}/common.py")

  tags = var.tags
}

# --- One curation job per curated table ---

module "curated_job" {
  source = "../glue-job"

  for_each = local.curated_tables

  job_name          = "meridian-curate-${each.key}-${var.env}"
  script_local_path = "${local.source_script_dir}/${each.key}.py"
  script_s3_key     = "${local.script_s3_prefix}/${each.key}.py"
  scripts_bucket    = var.scripts_bucket_name
  role_arn          = var.glue_role_arn

  default_arguments = merge(
    {
      "--extra-py-files"  = "s3://${aws_s3_object.common_module.bucket}/${aws_s3_object.common_module.key}"
      "--CLEANSED_BUCKET" = var.cleansed_bucket_name
      "--CURATED_BUCKET"  = var.curated_bucket_name
      "--TABLE"           = each.key
    },
    contains(keys(local.curated_sources), each.key) ? { "--SOURCE" = local.curated_sources[each.key] } : {}
  )

  tags = var.tags
}

# --- dim_patient / dim_staff: explicit tables, not crawled, so PII columns
# can carry a classification=pii tag ---

resource "aws_glue_catalog_table" "pii_dim" {
  for_each = local.pii_dim_key_columns

  name          = each.key
  database_name = aws_glue_catalog_database.this["curated"].name
  table_type    = "EXTERNAL_TABLE"
  parameters    = { "classification" = "parquet" }

  storage_descriptor {
    location      = "s3://${var.curated_bucket_name}/${each.key}/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = each.value
      type = "string"
    }

    dynamic "columns" {
      for_each = local.pii_columns

      content {
        name       = columns.value
        type       = "string"
        parameters = { "classification" = "pii" }
      }
    }
  }
}

# --- Crawler: every curated table except the 2 explicit PII dims above ---

module "curated_crawler" {
  source = "../glue-crawler"

  name          = "meridian-curated-crawler-${var.env}"
  database_name = aws_glue_catalog_database.this["curated"].name
  role_arn      = var.glue_role_arn
  s3_targets    = [for table in local.crawled_tables : "s3://${var.curated_bucket_name}/${table}/"]

  tags = var.tags
}
