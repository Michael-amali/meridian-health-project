variable "job_name" {
  description = "Name of the Glue job (e.g. meridian-cleanse-visits-dev)."
  type        = string
}

variable "script_local_path" {
  description = "Local path to the job's PySpark script - uploaded to script_s3_key."
  type        = string
}

variable "script_s3_key" {
  description = "S3 key (within scripts_bucket) to upload the script to."
  type        = string
}

variable "scripts_bucket" {
  description = "Name of the S3 bucket the job's script is uploaded to and run from."
  type        = string
}

variable "role_arn" {
  description = "ARN of the IAM role this job assumes."
  type        = string
}

variable "default_arguments" {
  description = "Job arguments (e.g. --RAW_BUCKET) passed to every run unless overridden at start-job-run time."
  type        = map(string)
  default     = {}
}

variable "glue_version" {
  description = "Glue runtime version."
  type        = string
  default     = "4.0"
}

variable "worker_type" {
  description = "Glue worker type."
  type        = string
  default     = "G.1X"
}

variable "number_of_workers" {
  description = "Number of Glue workers - 2 is the minimum Glue allows for a Spark job, and plenty for this project's data volume."
  type        = number
  default     = 2
}

variable "timeout_minutes" {
  description = "Job timeout in minutes."
  type        = number
  default     = 10
}

variable "max_retries" {
  description = "Automatic retries on failure. Kept at 0 so a genuine infrastructure failure shows up as a single FAILED run immediately, not after silently retrying - Phase 5 owns deciding whether/how to retry. Bad data no longer fails the job at all - see run_cleansing_job() in common.py."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags to apply to the job."
  type        = map(string)
  default     = {}
}
