output "stream_names" {
  description = "Map of stream key (vitals/prescriptions) to Kinesis stream name."
  value       = { for key, stream in aws_kinesis_stream.this : key => stream.name }
}

output "stream_arns" {
  description = "Map of stream key to Kinesis stream ARN."
  value       = { for key, stream in aws_kinesis_stream.this : key => stream.arn }
}

output "vitals_stream_name" {
  description = "Convenience output: the vitals stream's name, used by the alerting Lambda's event source mapping."
  value       = aws_kinesis_stream.this["vitals"].name
}

output "vitals_stream_arn" {
  description = "Convenience output: the vitals stream's ARN, used by IAM policies and the alerting Lambda's event source mapping."
  value       = aws_kinesis_stream.this["vitals"].arn
}
