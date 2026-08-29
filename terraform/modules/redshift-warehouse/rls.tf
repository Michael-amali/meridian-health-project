# Phase 6: facility-scoped row-level security, native to Redshift (not Lake
# Formation, which doesn't reach these tables - see schema.tf's header
# comment). Mechanism: a small mapping table from Redshift db_user to
# facility_id, one RLS policy that filters any table it's attached to down
# to the caller's own facility, and a demo persona per facility to prove it
# actually restricts rows (not just that the policy exists).
#
# Two real Redshift/Data-API behaviors, both confirmed by testing (not
# assumed from docs), drove the auth design below:
#   1. Redshift Serverless's Data API flatly rejects a --db-user parameter
#      on ExecuteStatement/BatchExecuteStatement when using an IAM caller's
#      own (temporary-credentials) identity - "DB User cannot be set during
#      a serverless request." So a facility persona can't be selected by
#      just passing a different db_user under one shared IAM identity.
#   2. Redshift never enforces RLS for a session that authenticated as a
#      superuser - not even after `SET SESSION AUTHORIZATION <role>` inside
#      that same session (confirmed against this exact namespace: querying
#      as the auto-created `admin` user, which is a superuser, after
#      switching session authorization to a demo user still returned every
#      facility's rows). So verifying RLS at all requires a session that
#      authenticated as a genuine non-superuser identity from the start.
#
# Both point at the same fix: each demo facility user gets a real password
# (not PASSWORD DISABLE) held in its own Secrets Manager secret, and each
# demo IAM role can decrypt only its own facility's secret - one role per
# facility, scoped by a real IAM resource (the secret ARN). An earlier
# version of this file instead tried a redshift-serverless:DbName/DbUser
# Condition directly on redshift-data:ExecuteStatement to scope one shared
# role per facility - IAM silently denied the whole statement (those keys
# aren't valid for that action, confirmed against AWS's own
# AmazonRedshiftDataFullAccess managed policy, which grants
# ExecuteStatement/BatchExecuteStatement with Resource "*" and no Condition
# at all) - worse than no condition, since it read as a security boundary
# that didn't exist.

locals {
  # Only these tables carry facility_id (every fact table, plus dim_facility
  # itself so a facility manager can't even browse other facilities' names) -
  # see this module's variables.tf header / the Phase 6 plan for how this was
  # confirmed against the actual curated schemas.
  rls_tables = [
    "dim_facility",
    "fact_patient_visit",
    "fact_bed_occupancy",
    "fact_staffing",
    "fact_claim",
    "fact_pharmacy_inventory",
    "fact_vitals_alert",
  ]

  # One demo persona per real facility (FAC01-03) - a much more convincing
  # proof that RLS actually varies by facility than a single demo user would
  # be.
  demo_facilities = {
    fac01_manager = "FAC01"
    fac02_manager = "FAC02"
    fac03_manager = "FAC03"
  }

  rls_setup_sql = join("\n", concat(
    [
      "CREATE TABLE IF NOT EXISTS facility_user_map (db_user VARCHAR(64), facility_id VARCHAR(10));",
      "CREATE ROLE facility_manager;",
      "CREATE RLS POLICY facility_scope WITH (facility_id VARCHAR(10)) USING (facility_id IN (SELECT facility_id FROM facility_user_map WHERE db_user = current_user));",
      # The USING clause above is evaluated as a subquery against
      # facility_user_map on behalf of whichever role is running the outer
      # query - confirmed by testing that granting SELECT only to the
      # facility_manager ROLE is not enough (Redshift errors "permission
      # denied to rls policy for relation facility_user_map" even though
      # has_table_privilege() for the querying user returns true). Only a
      # PUBLIC grant on this specific lookup table satisfies it. This is not
      # a real information leak: the table only maps a db_user to a
      # facility_id, nothing about facility_user_map itself is sensitive.
      "GRANT SELECT ON facility_user_map TO PUBLIC;",
    ],
    [for t in local.rls_tables : "ATTACH RLS POLICY facility_scope ON ${t} TO ROLE facility_manager;"],
    [for t in local.rls_tables : "GRANT SELECT ON ${t} TO ROLE facility_manager;"],
    # ATTACH RLS POLICY alone only registers the policy - it does not turn
    # enforcement on (confirmed by testing: svv_rls_attached_policy showed
    # is_pol_on = true but is_rls_on = false, and every facility manager saw
    # every facility's rows, until this ran). Same two-step shape as
    # PostgreSQL's CREATE POLICY + ALTER TABLE ... ENABLE ROW LEVEL SECURITY.
    [for t in local.rls_tables : "ALTER TABLE ${t} ROW LEVEL SECURITY ON;"],
  ))
}

resource "aws_redshiftdata_statement" "rls_setup" {
  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn

  sql = local.rls_setup_sql

  depends_on = [aws_redshiftdata_statement.create_table]

  # One-time setup, same reasoning as initial_load's lifecycle block in
  # schema.tf - and load-bearing here for a second reason: CREATE ROLE/
  # CREATE RLS POLICY/ATTACH RLS POLICY aren't idempotent (no "IF NOT
  # EXISTS" form), so once this has run successfully, re-running the whole
  # statement on a later sql change would fail with "already exists" rather
  # than reconciling anything.
  lifecycle {
    ignore_changes = all
  }
}

# --- Demo facility-manager personas: 1 native Redshift user + 1 password
# secret + 1 assumable IAM role (scoped to only that one secret) per
# facility ---

resource "random_password" "demo_facility_user" {
  for_each = local.demo_facilities

  length  = 24
  special = false # Redshift password rules reject several special characters; not needed for a demo credential
}

resource "aws_secretsmanager_secret" "demo_facility_user" {
  for_each = local.demo_facilities

  name = "meridian-redshift-${each.key}-${var.env}"
  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "demo_facility_user" {
  for_each = local.demo_facilities

  secret_id = aws_secretsmanager_secret.demo_facility_user[each.key].id
  secret_string = jsonencode({
    username = each.key
    password = random_password.demo_facility_user[each.key].result
  })
}

resource "aws_redshiftdata_statement" "demo_facility_users" {
  for_each = local.demo_facilities

  workgroup_name = aws_redshiftserverless_workgroup.this.workgroup_name
  database       = aws_redshiftserverless_namespace.this.db_name
  secret_arn     = aws_redshiftserverless_namespace.this.admin_password_secret_arn

  sql = <<-SQL
    CREATE USER ${each.key} PASSWORD '${random_password.demo_facility_user[each.key].result}';
    GRANT ROLE facility_manager TO ${each.key};
    INSERT INTO facility_user_map (db_user, facility_id) VALUES ('${each.key}', '${each.value}');
  SQL

  depends_on = [aws_redshiftdata_statement.rls_setup]

  # See schema.tf's initial_load resource for why this is needed here too:
  # the Data API redacts credential-bearing SQL text on read-back
  # (CREATE USER ... PASSWORD '...' included), producing the same permanent
  # phantom diff. This resource's only job is the one-time user setup.
  lifecycle {
    ignore_changes = all
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "facility_manager_demo" {
  for_each = local.demo_facilities

  name = "meridian-facility-manager-${lower(each.value)}-role-${var.env}"

  # Assumable by any principal in this account that's separately been given
  # sts:AssumeRole on this specific role ARN - same shape as the Phase 4 demo
  # roles, not pinned to today's caller identity.
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

# The real per-facility isolation lives here: each role can only decrypt its
# own facility's secret, so only that role can ever authenticate as that
# facility's demo user - unlike a Data API condition key (see this file's
# header comment), a secret ARN is a real, IAM-enforceable resource
# boundary.
resource "aws_iam_role_policy" "facility_manager_demo" {
  for_each = local.demo_facilities

  name = "redshift-data-api-access"
  role = aws_iam_role.facility_manager_demo[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOwnFacilitySecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.demo_facility_user[each.key].arn
      },
      {
        Sid      = "RunQueries"
        Effect   = "Allow"
        Action   = ["redshift-data:ExecuteStatement", "redshift-data:BatchExecuteStatement"]
        Resource = aws_redshiftserverless_workgroup.this.arn
      },
      {
        # DescribeStatement/GetStatementResult operate on a statement ID, not
        # a workgroup ARN - "*" is the only valid Resource shape for these,
        # matching AWS's own AmazonRedshiftDataFullAccess managed policy.
        Sid      = "ReadOwnQueryResults"
        Effect   = "Allow"
        Action   = ["redshift-data:GetStatementResult", "redshift-data:DescribeStatement"]
        Resource = "*"
      }
    ]
  })
}
