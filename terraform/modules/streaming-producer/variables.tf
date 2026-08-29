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

variable "schedule_enabled" {
  description = "Whether the EventBridge rule that invokes the producer is ENABLED. Set false in an environment that should exist but not produce synthetic events on its own (test/prod) - the Lambda is still created and can be invoked by hand."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
