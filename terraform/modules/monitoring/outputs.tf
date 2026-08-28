output "dashboard_name" {
  description = "Name of the CloudWatch dashboard - open it in the console at CloudWatch > Dashboards."
  value       = aws_cloudwatch_dashboard.pipeline.dashboard_name
}
