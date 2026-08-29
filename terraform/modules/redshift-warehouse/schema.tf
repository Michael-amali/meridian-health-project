# Phase 6: the 13-table star schema, created and loaded via the Redshift
# Data API (aws_redshiftdata_statement) rather than a JDBC/psql connection -
# this is the same "no bastion, no VPC client needed" reasoning as
# network.tf's header comment. The Data API's ExecuteStatement accepts
# multiple ;-separated SQL statements in one call, so a single resource can
# run more than one statement where that reads more naturally.
#
# Column types mirror the source Glue job's actual output schema (see
# src/glue_jobs/silver_to_gold/*.py and the cleansed source SCHEMA each one
# reads, in src/glue_jobs/bronze_to_silver/*.py) - not a redesign. In
# particular, every timestamp-shaped column (admission_ts, discharge_ts,
# event_ts, snapshot_date, shift_date, service_date) stays VARCHAR because
# that's genuinely its type in the curated Parquet - the curation jobs never
# cast these to a real timestamp. COPY fails on a type mismatch if declared
# otherwise, and ISO-8601 strings still sort correctly as text, so a SORTKEY
# on them behaves the same as it would on a real timestamp column.
#
# Note: Lake Formation's grants (terraform/modules/lake-formation-grants)
# only govern the Glue Catalog / Athena / Spectrum path - they do NOT apply
# to these native Redshift tables. Redshift has its own separate native
# permission system (GRANT/RBAC, used in rls.tf), which is why this module
# doesn't reuse anything from lake-formation-grants.

locals {
  table_columns = {
    dim_date = <<-SQL
      full_date DATE,
      date_key VARCHAR(10),
      year INTEGER,
      quarter INTEGER,
      month INTEGER,
      month_name VARCHAR(20),
      day_of_month INTEGER,
      day_of_week INTEGER,
      day_name VARCHAR(20),
      week_of_year INTEGER,
      is_weekend BOOLEAN
    SQL

    dim_department = <<-SQL
      department_id VARCHAR(10),
      department_name VARCHAR(50)
    SQL

    dim_drug = <<-SQL
      drug_name VARCHAR(100)
    SQL

    dim_facility = <<-SQL
      facility_id VARCHAR(10),
      facility_name VARCHAR(100)
    SQL

    dim_patient = <<-SQL
      patient_id VARCHAR(10),
      full_name VARCHAR(100),
      date_of_birth VARCHAR(20),
      phone VARCHAR(20),
      government_id VARCHAR(20)
    SQL

    dim_payer = <<-SQL
      payer VARCHAR(50)
    SQL

    dim_staff = <<-SQL
      staff_id VARCHAR(10),
      full_name VARCHAR(100),
      date_of_birth VARCHAR(20),
      phone VARCHAR(20),
      government_id VARCHAR(20)
    SQL

    fact_patient_visit = <<-SQL
      visit_id VARCHAR(40),
      patient_id VARCHAR(10),
      facility_id VARCHAR(10),
      department VARCHAR(50),
      visit_type VARCHAR(20),
      attending_staff_id VARCHAR(10),
      admission_ts VARCHAR(40),
      discharge_ts VARCHAR(40),
      still_admitted BOOLEAN,
      length_of_stay_hours DOUBLE PRECISION
    SQL

    fact_bed_occupancy = <<-SQL
      facility_id VARCHAR(10),
      department VARCHAR(50),
      total_beds INTEGER,
      occupied_beds INTEGER,
      snapshot_date VARCHAR(20),
      occupancy_rate DOUBLE PRECISION
    SQL

    fact_staffing = <<-SQL
      staff_id VARCHAR(10),
      facility_id VARCHAR(10),
      department VARCHAR(50),
      role VARCHAR(20),
      shift_date VARCHAR(20),
      shift_name VARCHAR(20),
      shift_start VARCHAR(20),
      shift_end VARCHAR(20)
    SQL

    fact_claim = <<-SQL
      claim_id VARCHAR(40),
      patient_id VARCHAR(10),
      facility_id VARCHAR(10),
      payer VARCHAR(50),
      claim_amount DOUBLE PRECISION,
      status VARCHAR(20),
      service_date VARCHAR(20)
    SQL

    fact_pharmacy_inventory = <<-SQL
      facility_id VARCHAR(10),
      drug_name VARCHAR(100),
      current_stock INTEGER,
      reorder_threshold INTEGER,
      unit_cost DOUBLE PRECISION,
      snapshot_date VARCHAR(20),
      stockout_risk BOOLEAN
    SQL

    fact_vitals_alert = <<-SQL
      event_id VARCHAR(40),
      patient_id VARCHAR(10),
      facility_id VARCHAR(10),
      heart_rate DOUBLE PRECISION,
      spo2 DOUBLE PRECISION,
      systolic_bp DOUBLE PRECISION,
      diastolic_bp DOUBLE PRECISION,
      temperature_c DOUBLE PRECISION,
      event_ts VARCHAR(40),
      heart_rate_breach BOOLEAN,
      spo2_breach BOOLEAN,
      systolic_bp_breach BOOLEAN,
      temperature_breach BOOLEAN
    SQL
  }

  # Dist/sort style per table. Dims are all tiny (3-1,096 rows) so
  # DISTSTYLE ALL (broadcast to every slice) is the standard choice - it
  # avoids redistribution on every join without needing a real key. Facts
  # with a genuinely high-cardinality foreign key (patient_id: 100 values,
  # staff_id: 30 values) use it as DISTKEY since that's the join every
  # dashboard query will make; the 2 facts with no such key (facility_id is
  # only 3 values, too low-cardinality to distribute on without skew) use
  # DISTSTYLE EVEN instead. SORTKEY is the column trend/detail queries
  # filter on most - almost always a date-shaped column.
  table_dist_sort = {
    dim_date                = "DISTSTYLE ALL SORTKEY (full_date)"
    dim_department          = "DISTSTYLE ALL"
    dim_drug                = "DISTSTYLE ALL"
    dim_facility            = "DISTSTYLE ALL"
    dim_patient             = "DISTSTYLE ALL"
    dim_payer               = "DISTSTYLE ALL"
    dim_staff               = "DISTSTYLE ALL"
    fact_patient_visit      = "DISTKEY (patient_id) SORTKEY (admission_ts)"
    fact_bed_occupancy      = "DISTSTYLE EVEN SORTKEY (snapshot_date, facility_id)"
    fact_staffing           = "DISTKEY (staff_id) SORTKEY (shift_date)"
    fact_claim              = "DISTKEY (patient_id) SORTKEY (service_date)"
    fact_pharmacy_inventory = "DISTSTYLE EVEN SORTKEY (snapshot_date, facility_id)"
    fact_vitals_alert       = "DISTKEY (patient_id) SORTKEY (event_ts)"
  }
}

# Phase 8: every aws_redshiftdata_statement in this module is a FIRE-ONCE
# resource - its entire job is to run some SQL at creation time. None of them
# should ever re-run, and each carries `lifecycle { ignore_changes = all }` to
# guarantee that.
#
# `all` rather than `[sql]` (which is what these originally had) because of how
# the Redshift Data API behaves over time: it only keeps statement history for
# about 24 hours. Once a statement ages out, the provider's refresh can no
# longer read it back and blanks `workgroup_name`, `secret_arn` and `sql` in
# state. Terraform then sees those as null -> value changes, all three of which
# force replacement, and plans to destroy and re-create all 30 statements. That
# is not cosmetic: re-running rls_setup or demo_facility_users FAILS outright,
# because CREATE ROLE / CREATE RLS POLICY / CREATE USER have no "IF NOT EXISTS"
# form, so the apply dies partway through. Ignoring [sql] alone did not prevent
# this - workgroup_name and secret_arn force replacement on their own.
#
# The trade-off, stated plainly: editing the SQL in this file will NOT change
# an environment that has already been applied. Changing the star schema means
# doing it deliberately against the warehouse (ALTER/DROP, or tear the
# environment down and re-apply), not by editing a string here and expecting
# Terraform to reconcile it. That was already true before this change - a
# CREATE TABLE IF NOT EXISTS against an existing table is a no-op - so nothing
# real is lost; the lifecycle block just stops Terraform from pretending
# otherwise.

resource "aws_redshiftdata_statement" "create_table" {
  for_each = local.table_columns

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn

  sql = "CREATE TABLE IF NOT EXISTS ${each.key} (${each.value}) ${local.table_dist_sort[each.key]};"

  # Run once, then never touch again - see the "fire-once statements" comment
  # at the top of this file for why this has to be `all` and not just [sql].
  lifecycle {
    ignore_changes = all
  }
}

# Initial load only - keeping this table's data fresh day to day is Phase 5's
# existing Step Functions pipelines' job (see the redshift_tables_to_load
# wiring in modules/step-functions-pipeline and
# terraform/environments/dev/main.tf), not this module.
resource "aws_redshiftdata_statement" "initial_load" {
  for_each = local.table_columns

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn

  # TRUNCATE + COPY, not a plain COPY - every curated table is a full-refresh
  # overwrite in S3 (see write_curated_table() in
  # src/glue_jobs/silver_to_gold/common.py), so this mirrors that same
  # idempotent, no-double-counting design instead of appending on re-apply.
  sql = <<-SQL
    TRUNCATE TABLE ${each.key};
    COPY ${each.key}
    FROM 's3://${var.curated_bucket_name}/${each.key}/'
    IAM_ROLE '${aws_iam_role.redshift_service.arn}'
    FORMAT AS PARQUET;
  SQL

  depends_on = [aws_redshiftdata_statement.create_table]

  # The Redshift Data API redacts the IAM_ROLE clause when it echoes back a
  # statement's query text (confirmed by testing: every one of these
  # resources reads back as IAM_ROLE '' after a successful apply, even
  # though the real ARN was what actually got submitted and ran) - without
  # this, Terraform would see a permanent phantom diff against this SQL and
  # want to "fix" it by re-running the load on every single apply forever.
  # Safe to ignore going forward for the same reason the header comment
  # above gives: this resource's only job is the one-time initial load: a
  # genuine schema/table change is picked up by the Step Functions pipeline's
  # own ongoing TRUNCATE + COPY, not by re-running this resource.
  lifecycle {
    ignore_changes = all
  }
}
