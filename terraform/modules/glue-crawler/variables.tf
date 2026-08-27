variable "name" {
  description = "Name of the Glue crawler."
  type        = string
}

variable "database_name" {
  description = "Glue Catalog database this crawler registers tables into."
  type        = string
}

variable "role_arn" {
  description = "ARN of the IAM role this crawler assumes."
  type        = string
}

variable "s3_targets" {
  description = "S3 paths this crawler scans - one Glue table is created per path that contains data."
  type        = list(string)
}

variable "table_prefix" {
  description = "Prefix added to every table name this crawler creates - use this when the last path segment of an s3_target would otherwise collide with an existing table name (e.g. a `_quarantine/bed_capacity/` target would create a table literally named `bed_capacity`, colliding with the real one)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the crawler."
  type        = map(string)
  default     = {}
}
