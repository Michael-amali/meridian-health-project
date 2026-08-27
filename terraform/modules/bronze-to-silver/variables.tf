variable "env" {
  description = "Environment name."
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw-layer S3 bucket the crawler and cleansing jobs read from."
  type        = string
}

variable "cleansed_bucket_name" {
  description = "Name of the cleansed-layer S3 bucket the cleansing jobs write to."
  type        = string
}

variable "scripts_bucket_name" {
  description = "Name of the S3 bucket Glue job scripts are uploaded to."
  type        = string
}

variable "logs_bucket_name" {
  description = "Name of the S3 bucket Athena query results are written to."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key, used to encrypt Athena query results."
  type        = string
}

variable "glue_role_arn" {
  description = "ARN of the glue_service IAM role (from iam-baseline) crawlers and jobs assume."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
