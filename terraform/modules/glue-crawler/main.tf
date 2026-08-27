# Generic single-crawler resource, reused by bronze-to-silver for both the raw
# and cleansed crawlers - the infrastructure shape is identical, only the
# database and S3 targets differ.
#
# No schedule is attached - Phase 3 runs crawlers manually for verification;
# Phase 5's orchestration decides when they run automatically.

resource "aws_glue_crawler" "this" {
  name          = var.name
  role          = var.role_arn
  database_name = var.database_name
  table_prefix  = var.table_prefix

  dynamic "s3_target" {
    for_each = var.s3_targets

    content {
      path = s3_target.value
    }
  }

  # A crawler re-run should update a table's schema in place (e.g. a source
  # gains a column) rather than create a versioned duplicate, and only log a
  # removed column instead of deleting it - safer default for a catalog other
  # jobs depend on.
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  tags = var.tags
}
