variable "env" {
  description = "Environment name."
  type        = string
}

variable "name" {
  description = "Short label for this pipeline (e.g. \"batch-daily\", \"streaming-curation\") - used to name every resource this module creates."
  type        = string
}

variable "cleanse_job_names" {
  description = "Bronze -> Silver Glue job names to run in parallel as the first stage."
  type        = list(string)
}

variable "curate_job_names" {
  description = "Silver -> Gold Glue job names to run in parallel as the final stage."
  type        = list(string)
}

variable "crawler_names" {
  description = "Glue crawlers to kick off between the cleanse and curate stages, to refresh Athena's view of the cleansed layer. Fired and forgotten rather than waited on - see the state machine definition's comment for why that's safe. An empty list skips this stage entirely."
  type        = list(string)
  default     = []
}

variable "sns_topic_arn" {
  description = "SNS topic to notify with this pipeline's success/failure outcome."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key - the SNS topic above is encrypted with it, so this pipeline's execution role needs decrypt/data-key access to publish to it."
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (cron(...) or rate(...)) that triggers this pipeline."
  type        = string
}

variable "redshift_tables_to_load" {
  description = "Curated tables this pipeline should TRUNCATE + COPY into Redshift after curation (see modules/redshift-warehouse for the table definitions). Empty list skips this stage entirely - the other redshift_* variables are only required when this is non-empty."
  type        = list(string)
  default     = []
}

variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup name the load statements run against."
  type        = string
  default     = null
}

variable "redshift_workgroup_arn" {
  description = "Redshift Serverless workgroup ARN - scopes the execution role's redshift-data:BatchExecuteStatement permission."
  type        = string
  default     = null
}

variable "redshift_database_name" {
  description = "Redshift database name the load statements run against."
  type        = string
  default     = null
}

variable "redshift_admin_secret_arn" {
  description = "Secrets Manager ARN holding the Redshift admin credentials (modules/redshift-warehouse's admin_secret_arn output) - the load statements authenticate as this admin, not this role's own IAM identity."
  type        = string
  default     = null
}

variable "curated_bucket_name" {
  description = "Curated-layer S3 bucket the Redshift load COPY statements read from."
  type        = string
  default     = null
}

variable "redshift_service_role_arn" {
  description = "IAM role Redshift's COPY command uses to read the curated bucket (modules/redshift-warehouse's redshift_service role) - referenced by the COPY statement's IAM_ROLE argument."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
