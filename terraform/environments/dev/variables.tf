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
