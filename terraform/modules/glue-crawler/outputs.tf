output "name" {
  description = "Name of the crawler (used for manual `aws glue start-crawler` verification)."
  value       = aws_glue_crawler.this.name
}
