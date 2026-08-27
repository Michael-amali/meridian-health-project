output "glue_service_role_arn" {
  description = "ARN of the IAM role Glue jobs/crawlers assume."
  value       = aws_iam_role.glue_service.arn
}

output "glue_service_role_name" {
  description = "Name of the IAM role Glue jobs/crawlers assume (used to attach further policies in later phases)."
  value       = aws_iam_role.glue_service.name
}

output "lambda_generator_role_arn" {
  description = "ARN of the IAM role the synthetic data generator Lambdas assume."
  value       = aws_iam_role.lambda_generator.arn
}

output "lambda_generator_role_name" {
  description = "Name of the IAM role the synthetic data generator Lambdas assume (used to attach further policies in later phases)."
  value       = aws_iam_role.lambda_generator.name
}

output "lambda_alerting_role_arn" {
  description = "ARN of the IAM role the vitals stream alerting Lambda assumes."
  value       = aws_iam_role.lambda_alerting.arn
}
