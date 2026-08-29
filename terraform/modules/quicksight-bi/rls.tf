# Phase 7: per-viewer row-level security, enforced by QuickSight.
#
# Phase 6 already built facility-scoped RLS natively in Redshift, and that
# still works for anyone querying Redshift directly. It cannot work here:
# every QuickSight viewer shares the single read-only database connection
# created in redshift-setup.tf, so Redshift only ever sees one identity no
# matter who is looking at the dashboard. QuickSight has to do the scoping,
# and it does it by joining every query against the "rules dataset" below on
# the viewer's own QuickSight user name.
#
# The column named UserName is not a naming choice - QuickSight looks for
# that exact name (and GroupName) in a VERSION_1 rules dataset. Redshift
# lowercases unquoted identifiers, hence the quoted alias.

locals {
  admin_user_arn = "arn:aws:quicksight:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:user/default/${var.quicksight_admin_user_name}"

  # Every action a dataset owner needs. Spelled out rather than abbreviated
  # because QuickSight has no wildcard or managed-policy equivalent here.
  data_set_owner_actions = [
    "quicksight:DescribeDataSet",
    "quicksight:DescribeDataSetPermissions",
    "quicksight:PassDataSet",
    "quicksight:DescribeIngestion",
    "quicksight:ListIngestions",
    "quicksight:UpdateDataSet",
    "quicksight:DeleteDataSet",
    "quicksight:CreateIngestion",
    "quicksight:CancelIngestion",
    "quicksight:UpdateDataSetPermissions",
  ]
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_quicksight_data_set" "facility_access" {
  data_set_id = "meridian-facility-access-${var.env}"
  name        = "Meridian facility access rules (${var.env})"

  # Direct query, not SPICE, unlike every other dataset here. A SPICE rules
  # dataset would only take effect after its next refresh, which makes
  # "change who can see what" a delayed operation - not what you want from an
  # access control mechanism.
  import_mode = "DIRECT_QUERY"

  physical_table_map {
    physical_table_map_id = "facility-access"

    custom_sql {
      data_source_arn = aws_quicksight_data_source.redshift.arn
      name            = "facility_access"
      sql_query       = "SELECT user_name AS \"UserName\", facility_id FROM ${local.access_map_table}"

      columns {
        name = "UserName"
        type = "STRING"
      }

      columns {
        name = "facility_id"
        type = "STRING"
      }
    }
  }

  permissions {
    principal = local.admin_user_arn
    actions   = local.data_set_owner_actions
  }

  tags = var.tags

  depends_on = [aws_redshiftdata_statement.facility_access_map]
}
