output "plan_role_arn" {
  description = "Role ARN the pull-request plan workflow assumes. Set as the AWS_PLAN_ROLE_ARN repository variable in GitHub."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arns" {
  description = "Map of environment name to the role ARN its apply job assumes. The workflow derives these by name, so nothing needs copying into GitHub."
  value       = { for env, role in aws_iam_role.apply : env => role.arn }
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider registered in this account."
  value       = aws_iam_openid_connect_provider.github.arn
}
