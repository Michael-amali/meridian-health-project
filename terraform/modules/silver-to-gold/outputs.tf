output "curated_database_name" {
  description = "Glue Catalog database holding the curated fact/dim tables."
  value       = aws_glue_catalog_database.this["curated"].name
}

output "curated_job_names" {
  description = "Map of table name to its curation Glue job name - useful for manual `aws glue start-job-run` testing."
  value       = { for table, job in module.curated_job : table => job.name }
}

output "curated_crawler_name" {
  description = "Name of the curated-layer crawler."
  value       = module.curated_crawler.name
}

output "curated_table_names" {
  description = "Names of every curated table (dims + facts) - used by lake-formation-grants to grant SELECT without re-deriving this list."
  value       = local.curated_tables
}

output "pii_table_names" {
  description = "Names of the curated tables with PII columns (dim_patient, dim_staff) - used by lake-formation-grants to know which tables need column exclusion instead of a plain grant."
  value       = local.pii_tables
}
