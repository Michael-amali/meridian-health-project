output "name" {
  description = "Name of the Glue job (used for manual `aws glue start-job-run` verification)."
  value       = aws_glue_job.this.name
}
