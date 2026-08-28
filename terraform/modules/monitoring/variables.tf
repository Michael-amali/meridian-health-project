variable "env" {
  description = "Environment name."
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic every alarm here publishes to."
  type        = string
}

variable "state_machine_arns" {
  description = "Map of pipeline label (e.g. \"batch-daily\") to its Step Functions state machine ARN - one failure alarm and one dashboard widget is created per entry."
  type        = map(string)
}

variable "kinesis_stream_names" {
  description = "Map of stream key (vitals/prescriptions) to stream name - one iterator-age alarm is created per entry."
  type        = map(string)
}

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
