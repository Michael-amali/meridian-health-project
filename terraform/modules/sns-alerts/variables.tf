variable "env" {
  description = "Environment name."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key, used to encrypt the topic at rest."
  type        = string
}

variable "alert_email" {
  description = "Email address to subscribe to pipeline alerts. Null skips the subscription (the topic is still created) - useful for an environment nobody should get paged for yet."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
