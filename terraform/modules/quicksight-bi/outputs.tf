output "executive_dashboard_url" {
  description = "Console URL for the Executive dashboard."
  value       = "https://${data.aws_region.current.name}.quicksight.aws.amazon.com/sn/dashboards/${aws_quicksight_dashboard.executive.dashboard_id}"
}

output "operational_dashboard_url" {
  description = "Console URL for the Operational & Clinical dashboard."
  value       = "https://${data.aws_region.current.name}.quicksight.aws.amazon.com/sn/dashboards/${aws_quicksight_dashboard.operational.dashboard_id}"
}

output "data_set_ids" {
  description = "Map of dataset key to QuickSight data set ID - use with `aws quicksight create-ingestion` to force a SPICE refresh outside the schedule."
  value       = { for key, data_set in aws_quicksight_data_set.dashboard : key => data_set.data_set_id }
}

output "facility_access_data_set_id" {
  description = "QuickSight data set ID of the row-level security rules dataset."
  value       = aws_quicksight_data_set.facility_access.data_set_id
}

output "redshift_reader_secret_arn" {
  description = "Secrets Manager ARN holding the read-only Redshift credentials QuickSight connects with."
  value       = aws_secretsmanager_secret.reader_user.arn
}
