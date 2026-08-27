output "function_name" {
  description = "Name of the streaming producer Lambda, useful for manual `aws lambda invoke` testing."
  value       = module.producer.function_name
}
