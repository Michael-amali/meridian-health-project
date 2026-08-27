variable "env" {
  description = "Environment name (dev, test, prod). Used in role names."
  type        = string
}

variable "bucket_arns" {
  description = "Map of layer name (raw/cleansed/curated/scripts/logs) to S3 bucket ARN, from the s3-data-lake module."
  type        = map(string)
}

variable "kms_key_arn" {
  description = "ARN of the data lake KMS key. Roles need this to read/write encrypted objects."
  type        = string
}

variable "stream_arns" {
  description = "Map of stream key (vitals/prescriptions) to Kinesis stream ARN, from the kinesis-streaming module. The lambda_generator role needs PutRecords on both."
  type        = map(string)
}

variable "vitals_stream_arn" {
  description = "ARN of the vitals Kinesis stream, from the kinesis-streaming module. The lambda_alerting role reads from this stream only - it never needs the prescriptions stream."
  type        = string
}

variable "alerts_table_arn" {
  description = "ARN of the active-alerts DynamoDB table, from the dynamodb-alerts module."
  type        = string
}

variable "tags" {
  description = "Common tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
