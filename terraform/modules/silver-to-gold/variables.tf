variable "env" {
  description = "Environment name."
  type        = string
}

variable "cleansed_bucket_name" {
  description = "Name of the cleansed-layer S3 bucket the curation jobs read from."
  type        = string
}

variable "curated_bucket_name" {
  description = "Name of the curated-layer S3 bucket the curation jobs write to."
  type        = string
}

variable "scripts_bucket_name" {
  description = "Name of the S3 bucket Glue job scripts are uploaded to."
  type        = string
}

variable "glue_role_arn" {
  description = "ARN of the glue_service IAM role (from iam-baseline) jobs and the crawler assume."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
