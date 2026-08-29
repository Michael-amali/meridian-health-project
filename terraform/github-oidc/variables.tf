variable "aws_region" {
  description = "AWS region. Only matters for the provider - IAM itself is global."
  type        = string
  default     = "us-east-1"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository."
  type        = string
  default     = "Michael-amali"
}

variable "github_repo" {
  description = "Repository name. Together with github_owner this is what the IAM trust policies pin to - a workflow in any other repository cannot assume these roles even with a valid GitHub token."
  type        = string
  default     = "meridian-health-project"
}

variable "environments" {
  description = "Environment names that get their own apply role. Each role trusts ONLY the matching GitHub Actions environment, which is what makes the approval gate on test/prod a real boundary rather than a UI convention."
  type        = list(string)
  default     = ["dev", "test", "prod"]
}

# --- Immutable subject claim IDs ---
#
# GitHub can mint the OIDC `sub` claim in two shapes:
#
#   repo:<owner>/<repo>:<context>                       (the classic form)
#   repo:<owner>@<ownerId>/<repo>@<repoId>:<context>     (the immutable form)
#
# The immutable form embeds GitHub's numeric IDs so that renaming an
# organisation or repository cannot quietly hand its AWS trust to whoever
# claims the freed-up name. This repository mints the immutable form, so the
# trust policies below have to match it - a policy written against the classic
# form alone fails with a bare "Not authorized to perform
# sts:AssumeRoleWithWebIdentity", which says nothing about why.
#
# Both forms are accepted, so the setup keeps working whichever GitHub sends.
# Find these with:
#   curl -s https://api.github.com/repos/<owner>/<repo> | jq '.id, .owner.id'

variable "github_owner_id" {
  description = "GitHub's numeric ID for the owner. Used in the immutable OIDC subject claim."
  type        = string
  default     = "77319495"
}

variable "github_repo_id" {
  description = "GitHub's numeric ID for the repository. Used in the immutable OIDC subject claim."
  type        = string
  default     = "1349929342"
}
