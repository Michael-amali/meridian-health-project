output "function_names" {
  description = "Map of source name to Lambda function name, useful for manual `aws lambda invoke` testing."
  value       = { for key, mod in module.generator : key => mod.function_name }
}
