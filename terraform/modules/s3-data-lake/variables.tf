variable "env" {
  description = "Environment name (dev, test, prod). Used in bucket names."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt all data lake buckets."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
