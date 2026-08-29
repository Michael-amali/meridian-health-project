# Phase 7: the Redshift side of the BI layer - a dedicated read-only database
# user for QuickSight, and the lookup table that drives QuickSight's own
# row-level security.
#
# Why a dedicated user rather than reusing the admin credentials Phase 6
# already has in Secrets Manager: the admin is a superuser, and handing a
# BI tool superuser credentials is exactly the kind of thing the RFP's
# governance section asks us not to do. This user can SELECT the 7 tables the
# dashboards read and nothing else.
#
# The IGNORE RLS grant below is load-bearing and easy to misread as a
# security hole, so: Phase 6 turned native Redshift RLS *on* for these tables
# (see modules/redshift-warehouse/rls.tf). In Redshift, once RLS is on for a
# table, a non-superuser with no RLS policy attached sees zero rows - so
# without IGNORE RLS this user reads nothing at all and every dashboard is
# blank. Per-viewer facility scoping still happens, just one layer up, in
# QuickSight itself (rls.tf in this module) - which is the only place it can
# happen, because all QuickSight viewers share this one database connection.

locals {
  # The only tables the dashboard datasets read (see datasets.tf). Listed
  # explicitly rather than granting on the whole schema so that adding a
  # dataset is a deliberate edit here, not something that happens by accident.
  readable_tables = [
    "dim_facility",
    "fact_patient_visit",
    "fact_bed_occupancy",
    "fact_staffing",
    "fact_claim",
    "fact_pharmacy_inventory",
    "fact_vitals_alert",
  ]

  reader_role = "meridian_quicksight_reader"
  reader_user = "quicksight_svc"

  # Table QuickSight reads its row-level security rules from. Lives in
  # Redshift (rather than a CSV in S3) purely so the whole BI layer has one
  # data source to connect through.
  access_map_table = "quicksight_user_facility_map"
}

resource "aws_redshiftdata_statement" "reader_role" {
  workgroup_name = var.redshift_workgroup_name
  database       = var.redshift_database_name
  secret_arn     = var.redshift_admin_secret_arn

  sql = join("\n", concat(
    [
      "CREATE ROLE ${local.reader_role};",
      "GRANT IGNORE RLS TO ROLE ${local.reader_role};",
    ],
    [for t in local.readable_tables : "GRANT SELECT ON ${t} TO ROLE ${local.reader_role};"],
  ))

  # Same reasoning as the one-time setup statements in
  # modules/redshift-warehouse: CREATE ROLE has no "IF NOT EXISTS" form, so
  # once this has run, re-running it on an edit would fail with "already
  # exists" rather than reconciling anything. Adding a table to
  # readable_tables therefore needs a one-off manual GRANT (or a taint of
  # this resource), which is the honest trade for keeping apply idempotent.
  lifecycle {
    ignore_changes = [sql]
  }
}

resource "random_password" "reader_user" {
  length  = 24
  special = false # Redshift rejects several special characters in passwords; length alone is plenty here
}

resource "aws_secretsmanager_secret" "reader_user" {
  name = "meridian-quicksight-redshift-${var.env}"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "reader_user" {
  secret_id = aws_secretsmanager_secret.reader_user.id
  secret_string = jsonencode({
    username = local.reader_user
    password = random_password.reader_user.result
  })
}

resource "aws_redshiftdata_statement" "reader_user" {
  workgroup_name = var.redshift_workgroup_name
  database       = var.redshift_database_name
  secret_arn     = var.redshift_admin_secret_arn

  sql = <<-SQL
    CREATE USER ${local.reader_user} PASSWORD '${random_password.reader_user.result}';
    GRANT ROLE ${local.reader_role} TO ${local.reader_user};
  SQL

  depends_on = [aws_redshiftdata_statement.reader_role]

  # The Redshift Data API blanks out the PASSWORD clause when it echoes this
  # statement's text back on read, which would otherwise show up as a
  # permanent diff on every plan. Same behaviour and same fix as the demo
  # users in modules/redshift-warehouse/rls.tf.
  lifecycle {
    ignore_changes = [sql]
  }
}

# Unlike the two statements above, this one IS meant to re-run whenever
# var.facility_access changes - changing the SQL replaces the resource, which
# re-submits it. DELETE + INSERT (rather than TRUNCATE) keeps the whole
# statement inside one transaction, so a failed re-apply can't leave the
# table empty and lock every viewer out of every row.
resource "aws_redshiftdata_statement" "facility_access_map" {
  workgroup_name = var.redshift_workgroup_name
  database       = var.redshift_database_name
  secret_arn     = var.redshift_admin_secret_arn

  sql = join("\n", concat(
    [
      "CREATE TABLE IF NOT EXISTS ${local.access_map_table} (user_name VARCHAR(128), facility_id VARCHAR(10));",
      "GRANT SELECT ON ${local.access_map_table} TO ROLE ${local.reader_role};",
      "DELETE FROM ${local.access_map_table};",
    ],
    [
      # A NULL facility_id is not "no access" - it is QuickSight's documented
      # way of saying "this user is not restricted on this field", which is
      # how the executive persona sees every facility.
      for user_name, facility_id in var.facility_access :
      "INSERT INTO ${local.access_map_table} (user_name, facility_id) VALUES ('${user_name}', ${facility_id == null || facility_id == "" ? "NULL" : "'${facility_id}'"});"
    ],
  ))

  depends_on = [aws_redshiftdata_statement.reader_role]
}
