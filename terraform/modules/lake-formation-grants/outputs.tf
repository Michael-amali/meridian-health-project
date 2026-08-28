output "demo_role_arns" {
  description = "Map of demo persona (analyst/executive) to its IAM role ARN - used to `aws sts assume-role` for masking verification."
  value       = { for key, role in aws_iam_role.demo : key => role.arn }
}
