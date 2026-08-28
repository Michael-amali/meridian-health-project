variable "env" {
  description = "Environment name."
  type        = string
}

variable "glue_service_role_arn" {
  description = "ARN of the glue_service IAM role (from iam-baseline) - granted unrestricted access to the curated database."
  type        = string
}

variable "curated_database_name" {
  description = "Glue Catalog database holding the curated fact/dim tables (from modules/silver-to-gold)."
  type        = string
}

variable "curated_resource_arn" {
  description = "ARN Lake Formation registered for the curated location (from modules/lake-formation-bootstrap) - needed for the pipeline role's DATA_LOCATION_ACCESS grant."
  type        = string
}

variable "curated_table_names" {
  description = "Names of every curated table (from modules/silver-to-gold)."
  type        = list(string)
}

variable "pii_table_names" {
  description = "Names of the curated tables with PII columns (from modules/silver-to-gold) - these get column-exclusion grants instead of a plain one."
  type        = list(string)
}

variable "logs_bucket_arn" {
  description = "ARN of the logs-layer S3 bucket the Athena workgroup writes query results to - demo roles need write access to its athena-results/ prefix to run any query at all, separate from the Lake Formation grants that gate the data itself."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key, so demo roles can decrypt/encrypt Athena query results (the workgroup's output location is SSE-KMS encrypted)."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
