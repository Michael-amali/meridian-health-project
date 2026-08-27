variable "env" {
  description = "Environment name."
  type        = string
}

variable "vitals_stream_arn" {
  description = "ARN of the vitals Kinesis stream this Lambda's event source mapping reads from."
  type        = string
}

variable "alerts_table_name" {
  description = "Name of the active-alerts DynamoDB table this Lambda writes to."
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the lambda_alerting IAM role (from iam-baseline) this function assumes."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
