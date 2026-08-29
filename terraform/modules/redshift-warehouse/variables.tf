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

variable "run_bootstrap_statements" {
  description = <<-DESC
    Whether to manage the one-time warehouse bootstrap SQL (create the tables,
    load them once, set up RLS, create the demo users).

    FALSE for an environment that already exists, and that is the default.

    Why this exists: the Redshift Data API only keeps statement history for
    about 24 hours. Once a statement ages out, the provider can no longer read
    it back and DROPS IT FROM STATE, so the next plan wants to CREATE it and the
    apply re-runs the SQL. CREATE ROLE / CREATE USER have no "IF NOT EXISTS"
    form, so that apply fails outright with `role "facility_manager" already
    exists` - meaning any apply more than a day after the last one breaks.
    (`lifecycle { ignore_changes }` does not help: it governs the diff for a
    resource that is still in state, not one that has vanished from it.)

    Gating them off means routine applies do not include these resources at all,
    so there is nothing to drop and nothing to re-run. Set it true only while
    standing up a NEW environment, then set it back to false.

    Turning it off is safe: aws_redshiftdata_statement has no delete API call -
    a statement is a historical record, not a live object - so removing these
    only drops state entries. The tables, roles and users stay exactly as they
    are in Redshift.
  DESC
  type        = bool
  default     = false
}
