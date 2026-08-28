output "curated_resource_arn" {
  description = "ARN Lake Formation registered for the curated location - used by lake-formation-grants' DATA_LOCATION_ACCESS grant."
  value       = aws_lakeformation_resource.curated.arn
}
