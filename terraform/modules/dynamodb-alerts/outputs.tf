output "table_name" {
  description = "Name of the active-alerts DynamoDB table."
  value       = aws_dynamodb_table.active_alerts.name
}

output "table_arn" {
  description = "ARN of the active-alerts DynamoDB table."
  value       = aws_dynamodb_table.active_alerts.arn
}
