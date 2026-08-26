variable "env" {
  description = "Environment name."
  type        = string
  default     = "test"
}

variable "aws_region" {
  description = "AWS region for this environment."
  type        = string
  default     = "us-east-1"
}
