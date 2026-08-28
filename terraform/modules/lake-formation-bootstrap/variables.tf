variable "env" {
  description = "Environment name."
  type        = string
}

variable "curated_bucket_arn" {
  description = "ARN of the curated-layer S3 bucket to register with Lake Formation."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key, so the Lake Formation data access role can decrypt/encrypt curated objects."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
