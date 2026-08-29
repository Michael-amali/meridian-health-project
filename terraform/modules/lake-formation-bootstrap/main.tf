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
#
# Phase 8: this is the ONE resource in this module that is account-wide, not
# per-environment - there is a single Lake Formation settings object for the
# whole AWS account, so dev/test/prod would all be writing to the same thing.
# Exactly one environment may own it (var.manage_account_settings = true, which
# is dev - see terraform/environments/*/terraform.tfvars). Two reasons this
# matters, both of which bite silently rather than erroring:
#   1. `terraform destroy` on a non-owning environment would DELETE the shared
#      settings, restoring the account-wide IAMAllowedPrincipals default grant
#      and quietly defeating dev's column-level masking.
#   2. `admins` is a whole-list replacement, so whichever environment applied
#      last would win, and the others would show permanent drift.
# test/prod still get everything else in this module (their own data-access
# role, their own curated location registration) - only this shared object is
# skipped, and they inherit its effect because it is account-wide anyway.
#
# Adding `count` renames this from `.this` to `.this[0]`; the moved block says
# that is a rename, so dev's already-applied settings are not destroyed and
# recreated (which would briefly restore the default grant it exists to remove).
moved {
  from = aws_lakeformation_data_lake_settings.this
  to   = aws_lakeformation_data_lake_settings.this[0]
}

resource "aws_lakeformation_data_lake_settings" "this" {
  count = var.manage_account_settings ? 1 : 0

  # The CI roles are admins alongside the human who applies locally.
  #
  # Without this, `terraform plan` from GitHub Actions fails on any database
  # created after these settings first landed - GetDatabase returns
  # "Insufficient Lake Formation permission(s): Required Describe on
  # meridian_curated_<env>". IAM read access is not enough on its own: for a
  # governed catalog resource, IAM and Lake Formation must BOTH allow the call.
  # (dev's raw/cleansed databases are the exception - they were created in
  # Phase 3, before these settings existed, so they kept the legacy
  # IAMAllowedPrincipals grant and are reachable on plain IAM. Every database
  # created since, in any environment, is not.)
  #
  # Admin is also what the apply roles genuinely need: a principal cannot grant
  # a Lake Formation permission it does not itself hold with grant option, and
  # modules/lake-formation-grants grants permissions to other principals.
  #
  # Making the PLAN role an admin does not make it dangerous, and this is the
  # part worth understanding: Lake Formation admin status is not an IAM policy.
  # Every mutating call still has to pass IAM first, and that role holds only
  # ReadOnlyAccess, which contains no lakeformation:GrantPermissions,
  # PutDataLakeSettings or RegisterResource. The two systems are ANDed, so
  # read-only in IAM stays read-only no matter what Lake Formation thinks.
  # This list is REPLACED wholesale on every apply, so it must not depend only
  # on who is running Terraform. An earlier version was
  # `[issuer_arn] + ci_role_names`, which looked fine locally and was broken:
  # applied from a laptop it produced [human, ci...], but applied from GitHub
  # Actions the issuer IS one of the CI roles, so the human silently vanished
  # from the list. The human then lost the ability to DESCRIBE any table a
  # crawler had created, `terraform plan` reported those tables and their grants
  # as gone, and the next apply tried to recreate all of it - none of which
  # names the real problem anywhere in the output.
  #
  # Listing all three sources explicitly means every apply converges on the same
  # set regardless of who runs it: the caller (so nobody can lock themselves
  # out), the named humans, and the CI roles.
  admins = distinct(concat(
    [data.aws_iam_session_context.current.issuer_arn],
    [for name in var.human_admin_user_names : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${name}"],
    [for name in var.ci_role_names : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${name}"],
  ))
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
