# Phase 8: the identity GitHub Actions uses to reach this AWS account.
#
# No access keys anywhere. GitHub mints a short-lived OIDC token for each
# workflow run, AWS is configured to trust that issuer, and the IAM trust
# policies below decide which workflow runs are allowed to become which role.
# Nothing long-lived is ever stored in a GitHub secret.

data "aws_caller_identity" "current" {}

locals {
  github_repo_path = "${var.github_owner}/${var.github_repo}"
}

# --- Trust the GitHub OIDC issuer -----------------------------------------
#
# One of these exists per AWS account. AWS validates this issuer against its
# own trust store rather than the thumbprint, so the value below no longer
# gates anything - but the argument is still part of the resource, and these
# are GitHub's published thumbprints.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# --- Plan role: read-only, usable from any branch --------------------------
#
# This is the role that runs on pull requests, so its trust policy is
# deliberately loose about WHICH ref is running (`:*` matches any branch, tag
# or PR) - a contributor has to be able to open a PR from a feature branch and
# see the plan. What keeps that safe is the permissions, not the trust: this
# role can read the account and read Terraform state, and can change nothing.
#
# It is still pinned to this one repository. A workflow in someone else's repo
# holding a perfectly valid GitHub token cannot assume it.
resource "aws_iam_role" "plan" {
  name        = "meridian-github-plan"
  description = "Read-only role assumed by GitHub Actions to run terraform plan on pull requests."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo_path}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# `terraform plan` reads the existing state object and writes nothing, so the
# workflow runs it with -lock=false and this role never needs DynamoDB or
# s3:PutObject. ReadOnlyAccess already covers s3:GetObject on the state bucket;
# this exists to say out loud that read is all it gets.
resource "aws_iam_role_policy" "plan_state_read" {
  name = "terraform-state-read"
  role = aws_iam_role.plan.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTerraformState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [
          "arn:aws:s3:::meridian-terraform-state-myk",
          "arn:aws:s3:::meridian-terraform-state-myk/*",
        ]
      }
    ]
  })
}

# --- Apply roles: one per environment, each pinned to its GitHub Environment
#
# This is the part that makes "a merge cannot reach prod on its own" true in
# IAM rather than only in the workflow file.
#
# When a workflow job declares `environment: prod`, GitHub puts
# `repo:<owner>/<repo>:environment:prod` in the token's `sub` claim. Only a job
# running in that environment gets that claim, and GitHub will not start such a
# job until the environment's required reviewers have approved it. So the prod
# role is unassumable until a human clicks approve - even by someone who can
# push directly to master, and even if they edit the workflow file, because the
# claim is minted by GitHub, not by the workflow.
#
# StringEquals, not StringLike, and no wildcard: each role trusts exactly one
# environment string.
resource "aws_iam_role" "apply" {
  for_each = toset(var.environments)

  name        = "meridian-github-apply-${each.key}"
  description = "Role assumed by GitHub Actions to run terraform apply against the ${each.key} environment. Assumable only from the '${each.key}' GitHub Actions environment."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo_path}:environment:${each.key}"
          }
        }
      }
    ]
  })
}

# AdministratorAccess, stated plainly rather than hidden behind a hand-written
# policy that would drift: this stack creates IAM roles, KMS grants, Lake
# Formation settings, Redshift, QuickSight and Glue resources, so anything
# narrower would be a long list that breaks every time a phase adds a service,
# and a broken apply is worse than an honest grant here.
#
# What actually contains this in a real deployment is the separation above -
# three roles, each reachable only from its own approval-gated environment -
# plus one AWS account per environment so a prod role cannot see dev at all.
# This project runs a single account by design (see the capstone's cost
# constraints), so the environment gate is the boundary that does the work.
resource "aws_iam_role_policy_attachment" "apply_admin" {
  for_each = aws_iam_role.apply

  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
