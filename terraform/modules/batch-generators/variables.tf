variable "env" {
  description = "Environment name."
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw-layer S3 bucket generators write to."
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the lambda_generator IAM role (from iam-baseline) these functions assume."
  type        = string
}

variable "schedules_enabled" {
  description = "Whether the EventBridge rules that invoke these generators are ENABLED. Set false in an environment that should exist but not generate synthetic data on its own (test/prod) - the Lambdas are still created and can be invoked by hand with `aws lambda invoke`."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
