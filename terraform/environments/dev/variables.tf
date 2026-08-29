# Phase 8: this file is IDENTICAL in dev/, test/ and prod/, and so is main.tf
# and outputs.tf next to it. The only things that differ between the three
# environments are backend.tf (a different state key) and terraform.tfvars
# (the values below). That is deliberate: if the environments differed in
# code, "we promoted this change through dev -> test -> prod" would not mean
# very much, because the thing running in prod would not be the thing tested
# in dev. Keep it that way - if you need an environment to behave differently,
# add a variable here and set it in that environment's tfvars.

variable "env" {
  description = "Environment name. Every resource name is suffixed with it, so this is what keeps dev/test/prod from colliding inside the single shared AWS account."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.env)
    error_message = "env must be one of: dev, test, prod."
  }
}

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address subscribed to the Phase 5 pipeline alerts SNS topic. Null skips the subscription (the topic is still created)."
  type        = string
  default     = null
}

variable "quicksight_admin_user_name" {
  description = "Existing QuickSight user (in the 'default' namespace) that owns the Phase 7 datasets and dashboards. QuickSight users come from signing up for QuickSight, not from Terraform, so this has to match a real one - check with `aws quicksight list-users --namespace default`."
  type        = string
}

variable "quicksight_facility_access" {
  description = "QuickSight user name -> facility_id the user may see in the dashboards. null means unrestricted, which is the executive persona. The three facility-manager entries mirror the Phase 6 Redshift demo personas, so the same story holds whether you query Redshift directly or open a dashboard."
  type        = map(string)
}

# --- Cost / activity knobs -------------------------------------------------
#
# Everything below exists so that an environment can be structurally identical
# to dev - same modules, same resources, same wiring - while sitting idle
# instead of generating and processing synthetic data around the clock. This
# is what makes it affordable to keep test and prod deployed.
#
# Nothing here removes a resource. Every Lambda, Glue job, state machine and
# dataset is still created and can still be run by hand; these only control
# whether AWS runs them unattended on a timer.

variable "batch_schedules_enabled" {
  description = <<-DESC
    Whether the BATCH side runs on its own EventBridge schedules: the five
    synthetic CSV generators (06:00-06:20 UTC) and the batch-daily Step
    Functions pipeline that cleanses and curates what they produce (08:00 UTC).

    This is the side that carries the project's daily story, so it is on in dev
    and off in the idle environments.
  DESC
  type        = bool
  default     = false
}

variable "streaming_enabled" {
  description = <<-DESC
    Whether the STREAMING side runs: the Kinesis producer Lambda, the vitals
    alerting consumer that reads the stream, and the streaming-curation Step
    Functions pipeline that fires every 30 minutes.

    All three are one switch because they only make sense together. A consumer
    with no producer still bills for polling an empty stream around the clock,
    and a curation pipeline with no new events still wakes Glue and Redshift 48
    times a day to process nothing.

    Off everywhere at the moment, including dev - this is the expensive half of
    the platform and there is no need to run it continuously between demos. The
    Lambdas, the state machine and the streams all still exist; turn this on, or
    invoke them by hand, when you actually want streaming data flowing.
  DESC
  type        = bool
  default     = false
}

variable "quicksight_refresh_schedules_enabled" {
  description = "Whether the SPICE datasets refresh on a schedule. Off in an idle environment - a scheduled refresh wakes Redshift Serverless and bills RPU seconds to reload data that did not change. The datasets still exist and can be refreshed on demand with `aws quicksight create-ingestion`."
  type        = bool
  default     = false
}

variable "redshift_base_capacity" {
  description = "Redshift Serverless base capacity in RPUs. 8 is the smallest AWS accepts and is correct for every environment here - Redshift Serverless bills only while a query is actually running, so an idle workgroup at 8 RPU costs nothing."
  type        = number
  default     = 8
}

variable "manage_lake_formation_account_settings" {
  description = <<-DESC
    Whether THIS environment owns the account-wide Lake Formation settings.

    There is exactly one aws_lakeformation_data_lake_settings object per AWS
    account, and this project runs all three environments in one account, so
    only one of them may manage it. dev does; test and prod set this false.

    Do not flip this on for a second environment. Two owners means whichever
    applied last silently wins, and a `terraform destroy` of the non-owning
    environment would delete the shared object and re-enable the default
    IAMAllowedPrincipals grant account-wide - which is precisely what Phase 4's
    column-level PII masking depends on being switched off.
  DESC
  type        = bool
  default     = false
}
