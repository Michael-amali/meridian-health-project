variable "env" {
  description = "Environment name (dev, test, prod). Used in role names."
  type        = string
}

variable "bucket_arns" {
  description = "Map of layer name (raw/cleansed/curated/scripts/logs) to S3 bucket ARN, from the s3-data-lake module."
  type        = map(string)
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key. Roles need this to read/write encrypted objects."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
