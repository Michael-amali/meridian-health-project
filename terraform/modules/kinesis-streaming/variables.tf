variable "env" {
  description = "Environment name."
  type        = string
}

variable "raw_bucket_name" {
  description = "Name of the raw-layer S3 bucket Firehose delivers into."
  type        = string
}

variable "raw_bucket_arn" {
  description = "ARN of the raw-layer S3 bucket Firehose delivers into."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key, used to encrypt the streams and to let Firehose write KMS-encrypted objects to the raw bucket."
  type        = string
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
