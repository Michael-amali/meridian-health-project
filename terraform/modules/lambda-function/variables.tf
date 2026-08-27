variable "function_name" {
  description = "Name of the Lambda function (e.g. meridian-gen-visits-dev)."
  type        = string
}

variable "source_dir" {
  description = "Local directory to zip and deploy as the function's code. Every file in this directory is included, so keep related handlers grouped intentionally (see src/generators/batch for an example)."
  type        = string
}

variable "handler" {
  description = "Lambda handler, e.g. 'visits.handler' for a handler() function in visits.py."
  type        = string
}

variable "role_arn" {
  description = "ARN of the IAM role this function assumes."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Function timeout in seconds."
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Function memory in MB."
  type        = number
  default     = 128
}

variable "environment_variables" {
  description = "Environment variables to expose to the function."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "How long to keep the function's CloudWatch Logs - short by default, this is synthetic demo data, not something we need to retain indefinitely."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags to apply to the function and its log group."
  type        = map(string)
  default     = {}
}
