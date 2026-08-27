output "raw_database_name" {
  description = "Glue Catalog database holding the raw tables."
  value       = aws_glue_catalog_database.this["raw"].name
}

output "cleansed_database_name" {
  description = "Glue Catalog database holding the cleansed tables (and dq_results)."
  value       = aws_glue_catalog_database.this["cleansed"].name
}

output "cleansing_job_names" {
  description = "Map of source name to its cleansing Glue job name - useful for manual `aws glue start-job-run` testing."
  value       = { for source, job in module.cleansing_job : source => job.name }
}

output "raw_crawler_name" {
  description = "Name of the raw-layer crawler."
  value       = module.raw_crawler.name
}

output "cleansed_crawler_name" {
  description = "Name of the cleansed-layer crawler."
  value       = module.cleansed_crawler.name
}

output "quarantine_crawler_name" {
  description = "Name of the quarantine crawler (tables come out named quarantine_<source>)."
  value       = module.quarantine_crawler.name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup to run verification queries in."
  value       = aws_athena_workgroup.analytics.name
}
