variable "env" {
  description = "Environment name."
  type        = string
}

variable "curated_bucket_name" {
  description = "Name of the curated-layer S3 bucket this warehouse loads from."
  type        = string
}

variable "curated_bucket_arn" {
  description = "ARN of the curated-layer S3 bucket - scopes the Redshift service role's read access."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key - encrypts the Redshift namespace and decrypts curated Parquet during COPY."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
