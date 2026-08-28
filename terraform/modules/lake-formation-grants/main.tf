# Phase 4: Lake Formation governance, part 2 of 2 - permission grants against
# the curated database/tables that modules/silver-to-gold creates. This
# module is applied AFTER silver-to-gold (see the depends_on on this
# module's declaration in terraform/environments/dev/main.tf) - these grants
# need the curated database/tables to already exist, the opposite ordering
# from modules/lake-formation-bootstrap (see that module's header for why
# this is 2 modules instead of 1).

data "aws_caller_identity" "current" {}

locals {
  demo_roles     = toset(["analyst", "executive"])
  non_pii_tables = toset([for t in var.curated_table_names : t if !contains(var.pii_table_names, t)])
  pii_columns    = ["full_name", "date_of_birth", "phone", "government_id"]
}

# --- Pipeline role: full, unrestricted access - it's what the crawler and
# curation jobs themselves run as, so it needs to see everything ---
#
# SELECT isn't a valid permission at database scope (confirmed against the
# real API - combining it with the database-level permissions below fails
# with "Permissions modification is invalid") - it only applies to
# table/table_with_columns resources. A wildcard table grant covers SELECT
# across every table in the database, including ones that don't exist yet -
# which also sidesteps the "table not found" problem the demo roles' named
# per-table grants below run into before the curated crawler has run once.
resource "aws_lakeformation_permissions" "glue_service_database" {
  principal   = var.glue_service_role_arn
  permissions = ["CREATE_TABLE", "ALTER", "DROP", "DESCRIBE"]

  database {
    name = var.curated_database_name
  }
}

resource "aws_lakeformation_permissions" "glue_service_tables" {
  principal   = var.glue_service_role_arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = var.curated_database_name
    wildcard      = true
  }
}

# Required alongside CREATE_TABLE/ALTER above, or the crawler can't actually
# create tables under the registered curated location - Lake Formation
# grants data-location access separately from database/table permissions.
resource "aws_lakeformation_permissions" "glue_service_data_location" {
  principal   = var.glue_service_role_arn
  permissions = ["DATA_LOCATION_ACCESS"]

  data_location {
    arn = var.curated_resource_arn
  }
}

# --- Demo roles: prove the column exclusion actually works ---
#
# Not real personas yet (Phase 6/7 add real facility-scoped row-level
# security) - just enough to verify masking end-to-end: assume one of these,
# query dim_patient, and confirm the PII columns are gone.

resource "aws_iam_role" "demo" {
  for_each = local.demo_roles

  name = "meridian-${each.key}-role-${var.env}"

  # Assumable by any principal in this account that's separately been given
  # sts:AssumeRole on this specific role ARN - not pinned to today's caller
  # identity, which would break if the applier ever changes.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# lakeformation:GetDataAccess only ever supports Resource = "*" - it's what
# lets Athena request column-filtered temporary credentials on a demo role's
# behalf. These roles deliberately have no native S3 permission on the
# curated bucket at all - Lake Formation is the only path to the data, which
# is the whole point of this verification.
resource "aws_iam_role_policy" "demo_lakeformation_access" {
  for_each = aws_iam_role.demo

  name = "lakeformation-data-access"
  role = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "GetVendedCredentials"
        Effect   = "Allow"
        Action   = ["lakeformation:GetDataAccess"]
        Resource = "*"
      },
      {
        Sid    = "AthenaAndCatalogRead"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetDatabase",
          "glue:GetDatabases",
        ]
        Resource = "*"
      },
      {
        # Separate from the Lake Formation grants above, which gate the
        # curated data itself: Athena still needs to write its own query
        # result files somewhere, and that's plain S3, not Lake Formation.
        # Scoped to only the athena-results/ prefix, not the whole logs
        # bucket.
        Sid      = "AthenaQueryResultsBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.logs_bucket_arn, "${var.logs_bucket_arn}/athena-results/*"]
      },
      {
        Sid    = "UseDataLakeKmsKeyForAthenaResults"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Non-PII tables: plain SELECT+DESCRIBE, every column visible.
resource "aws_lakeformation_permissions" "demo_non_pii" {
  for_each = {
    for pair in setproduct(tolist(local.demo_roles), tolist(local.non_pii_tables)) : "${pair[0]}.${pair[1]}" => pair
  }

  principal   = aws_iam_role.demo[each.value[0]].arn
  permissions = ["SELECT", "DESCRIBE"]

  table {
    database_name = var.curated_database_name
    name          = each.value[1]
  }
}

# PII tables: SELECT only (no separate DESCRIBE grant here) - Lake Formation
# doesn't allow granting a table-scoped permission and a column-scoped
# permission to the same principal on the same table at once (confirmed
# against the real API: adding a plain `table {}` DESCRIBE grant for a
# principal that also holds this table_with_columns SELECT grant fails with
# "Permissions modification is invalid", consistently and regardless of
# apply order). The demo roles' IAM policy already grants glue:GetTable/
# GetTables for catalog browsing; this LF grant is what actually authorizes
# reading data, which is the only thing this phase needs to verify.
#
# Deliberately a per-table grant, not a database-level one - Lake Formation
# grants are additive (no "deny"), so if either demo role ever also got a
# database-level SELECT, that broader grant would silently reinstate these
# excluded columns.
resource "aws_lakeformation_permissions" "demo_pii_masked" {
  for_each = {
    for pair in setproduct(tolist(local.demo_roles), var.pii_table_names) : "${pair[0]}.${pair[1]}" => pair
  }

  principal   = aws_iam_role.demo[each.value[0]].arn
  permissions = ["SELECT"]

  table_with_columns {
    database_name         = var.curated_database_name
    name                  = each.value[1]
    wildcard              = true
    excluded_column_names = local.pii_columns
  }
}
