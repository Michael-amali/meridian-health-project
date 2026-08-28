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

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
