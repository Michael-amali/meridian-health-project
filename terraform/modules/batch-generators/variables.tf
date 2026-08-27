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

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
