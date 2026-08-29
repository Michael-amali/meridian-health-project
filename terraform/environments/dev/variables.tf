variable "env" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address subscribed to the Phase 5 pipeline alerts SNS topic. Null skips the subscription (the topic is still created)."
  type        = string
  default     = "michaelacheampongy@gmail.com"
}

variable "quicksight_admin_user_name" {
  description = "Existing QuickSight user (in the 'default' namespace) that owns the Phase 7 datasets and dashboards. QuickSight users come from signing up for QuickSight, not from Terraform, so this has to match a real one - check with `aws quicksight list-users --namespace default`."
  type        = string
  default     = "Michael-Ach"
}

variable "quicksight_facility_access" {
  description = "QuickSight user name -> facility_id the user may see in the dashboards. null means unrestricted, which is the executive persona. The three facility-manager entries mirror the Phase 6 Redshift demo personas, so the same story holds whether you query Redshift directly or open a dashboard."
  type        = map(string)
  default = {
    "Michael-Ach"   = null
    "fac01-manager" = "FAC01"
    "fac02-manager" = "FAC02"
    "fac03-manager" = "FAC03"
  }
}
