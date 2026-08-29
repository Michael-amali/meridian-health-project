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
