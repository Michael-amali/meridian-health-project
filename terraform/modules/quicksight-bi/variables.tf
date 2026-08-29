variable "env" {
  description = "Environment name."
  type        = string
}

variable "quicksight_admin_user_name" {
  description = "QuickSight user name that owns the data source, datasets and dashboards this module creates. Must already exist in the QuickSight 'default' namespace - QuickSight users are created by signing up, not by Terraform."
  type        = string
}

# --- Redshift connection details (all from module.redshift_warehouse) ---

variable "redshift_workgroup_name" {
  description = "Redshift Serverless workgroup name - used to run this module's own setup SQL through the Data API."
  type        = string
}

variable "redshift_database_name" {
  description = "Redshift database holding the star schema."
  type        = string
}

variable "redshift_admin_secret_arn" {
  description = "Secrets Manager ARN of the Redshift admin credentials. Used only to run setup SQL (create the read-only QuickSight user, its grants, and the RLS mapping table) - QuickSight itself never uses the admin credentials."
  type        = string
}

variable "redshift_endpoint_address" {
  description = "Private DNS host name of the Redshift Serverless workgroup endpoint."
  type        = string
}

variable "redshift_endpoint_port" {
  description = "Port the Redshift Serverless workgroup endpoint listens on."
  type        = number
}

variable "redshift_vpc_id" {
  description = "VPC the Redshift workgroup runs in - the QuickSight VPC connection's ENIs go in this same VPC."
  type        = string
}

variable "redshift_subnet_ids" {
  description = "Private subnets to place the QuickSight VPC connection's ENIs in. QuickSight requires at least 2 availability zones."
  type        = list(string)
}

variable "redshift_security_group_id" {
  description = "Security group attached to the Redshift workgroup. This module adds an inbound rule to it allowing 5439 from the QuickSight security group it creates."
  type        = string
}

# --- Row-level security ---

variable "facility_access" {
  description = <<-DESC
    Maps a QuickSight user name to the facility_id that user is allowed to see
    in every dashboard dataset. A null value means "no restriction" - that user
    sees every facility, which is what the executive persona needs.

    QuickSight applies these rules itself (see rls.tf): the dashboards connect
    to Redshift as one shared read-only user, so Phase 6's native Redshift RLS
    can't tell one dashboard viewer from another.
  DESC
  type        = map(string)
}

variable "refresh_schedules_enabled" {
  description = "Whether the SPICE refresh schedules are created. Set false in an environment whose pipelines are also switched off (test/prod) - a refresh there would wake Redshift and bill RPU seconds to reload data that never changed. The datasets still exist and can be refreshed on demand with `aws quicksight create-ingestion`."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}

variable "run_bootstrap_statements" {
  description = <<-DESC
    Whether to manage the one-time Redshift setup SQL this module needs (create
    the read-only reader role and the reader user it connects as).

    Same reasoning and same default as run_bootstrap_statements in
    modules/redshift-warehouse - see that variable for the full explanation of
    why the Data API's 24-hour statement history makes these unsafe to leave
    under routine management.

    Note the facility access map is deliberately NOT gated by this: its SQL is
    idempotent (CREATE TABLE IF NOT EXISTS, then DELETE and re-INSERT), and it
    has to keep tracking the facility_access variable, so re-running it is both
    safe and the point.
  DESC
  type        = bool
  default     = false
}
