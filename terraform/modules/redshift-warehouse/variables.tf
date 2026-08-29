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

variable "base_capacity" {
  description = "Redshift Serverless base capacity in RPUs. 8 is the smallest value AWS accepts, and it is what every environment in this project uses - capstone-scale data never needs more. Exposed as a variable so an environment can be sized up deliberately rather than by editing the module."
  type        = number
  default     = 8
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
