# Phase 4: Lake Formation governance, part 1 of 2 - account-level settings
# and resource registration for the curated layer only (raw/cleansed stay on
# plain IAM, exactly as Phase 3 left them - neither is registered here).
#
# This module has NO dependency on modules/silver-to-gold, and that's
# deliberate: terraform/environments/dev/main.tf gives module.silver_to_gold
# a depends_on this module, so the account settings below (in particular,
# turning off the default IAMAllowedPrincipals grant) land BEFORE the curated
# database/tables exist - otherwise they'd be created with that default grant
# already attached, which would defeat modules/lake-formation-grants' column
# exclusions entirely. See modules/lake-formation-grants for the permission
# grants themselves, which - the opposite way round - DO need the curated
# database/tables to already exist, hence the 3-module split instead of one.

data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "current" {
  arn = data.aws_caller_identity.current.arn
}

# --- Account-level settings ---
#
# create_*_default_permissions = [] stops every NEWLY CREATED database/table
# account-wide (not just curated) from automatically getting the legacy
# IAMAllowedPrincipals "Super" grant - without this, a plain IAM permission
# would keep bypassing the column-exclusion grants below regardless of what
# they say. This does NOT retroactively touch raw/cleansed (created in Phase
# 3, before this resource ever existed), so that layer keeps working
# unmodified. It DOES mean any future database created anywhere in this
# account (a new raw source, a Phase 6 Redshift Spectrum schema, ...) will
# also need explicit Lake Formation grants from that point on.
#
# admins must be non-empty (an empty list here would lock everyone out of
# managing Lake Formation permissions) - aws_iam_session_context resolves to
# the underlying role/user ARN even when applying as an assumed role, so
# whoever runs `terraform apply` doesn't lock themselves out.
#
# create_database_default_permissions / create_table_default_permissions are
# blocks in this provider version, not plain list arguments - simply
# omitting them (rather than assigning `= []`) is what tells the provider
# "zero default-permission entries", i.e. no automatic IAMAllowedPrincipals
# grant for anything created after this applies.
resource "aws_lakeformation_data_lake_settings" "this" {
  admins = [data.aws_iam_session_context.current.issuer_arn]
}

# --- Curated location registration ---
#
# A dedicated role, not use_service_linked_role: the Lake Formation
# service-linked role can't take a customer-managed IAM policy, and this
# bucket's objects are KMS-encrypted with a customer-managed key (see
# modules/kms) - granting the SLR access would mean editing that key's
# policy from this module, reaching into a Phase 1 module. This role keeps
# that entirely self-contained (modules/kms's key policy already delegates
# "who can use this key" to IAM, so a plain inline policy here is enough -
# no key policy change needed).
#
# This is a one-way choice: AWS doesn't support switching a registered
# location between a service-linked role and a custom role_arn later without
# deregistering and re-granting everything under it.
resource "aws_iam_role" "lakeformation_data_access" {
  name = "meridian-lakeformation-data-access-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lakeformation.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "lakeformation_data_access" {
  name = "curated-bucket-access"
  role = aws_iam_role.lakeformation_data_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListCuratedBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.curated_bucket_arn
      },
      {
        Sid      = "ReadWriteCuratedObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.curated_bucket_arn}/*"
      },
      {
        Sid    = "UseDataLakeKmsKey"
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

resource "aws_lakeformation_resource" "curated" {
  arn      = var.curated_bucket_arn
  role_arn = aws_iam_role.lakeformation_data_access.arn
}
