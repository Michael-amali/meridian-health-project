output "topic_arn" {
  description = "ARN of the pipeline alerts SNS topic."
  value       = aws_sns_topic.pipeline_alerts.arn
}
