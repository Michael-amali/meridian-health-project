variable "env" {
  description = "Environment name."
  type        = string
}

variable "vitals_stream_name" {
  description = "Name of the vitals Kinesis stream to write to."
  type        = string
}

variable "prescriptions_stream_name" {
  description = "Name of the prescriptions Kinesis stream to write to."
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the lambda_generator IAM role (from iam-baseline) this function assumes."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
