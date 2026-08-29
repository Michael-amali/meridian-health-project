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

variable "manage_account_settings" {
  description = "Whether THIS environment owns the account-wide aws_lakeformation_data_lake_settings object. There is only one per AWS account, so exactly one environment may set this true (dev does) - see the long comment above that resource in main.tf for why a second owner is actively harmful."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
