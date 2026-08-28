output "workgroup_name" {
  description = "Redshift Serverless workgroup name - used by the Step Functions load stage to target COPY/TRUNCATE statements."
  value       = aws_redshiftserverless_workgroup.this.workgroup_name
}

output "workgroup_arn" {
  description = "Redshift Serverless workgroup ARN - used to scope IAM permissions for both the Step Functions load stage and the demo facility-manager roles."
  value       = aws_redshiftserverless_workgroup.this.arn
}

output "namespace_name" {
  description = "Redshift Serverless namespace name."
  value       = aws_redshiftserverless_namespace.this.namespace_name
}

output "database_name" {
  description = "Redshift database name."
  value       = aws_redshiftserverless_namespace.this.db_name
}

output "admin_secret_arn" {
  description = "Secrets Manager ARN holding the Redshift admin credentials - use this to run manual verification queries via the Data API."
  value       = aws_redshiftserverless_namespace.this.admin_password_secret_arn
}

output "redshift_service_role_arn" {
  description = "IAM role Redshift COPY uses to read the curated bucket - passed as the IAM_ROLE argument by the Step Functions load stage's COPY statements too."
  value       = aws_iam_role.redshift_service.arn
}

output "facility_manager_demo_role_arns" {
  description = "Map of facility (FAC01/FAC02/FAC03) to its demo facility-manager IAM role ARN. Assume one, read its facility's secret (demo_facility_user_secret_arns), and call the Redshift Data API with that secret to verify RLS restricts rows to that facility."
  value       = { for user, facility in local.demo_facilities : facility => aws_iam_role.facility_manager_demo[user].arn }
}

output "demo_facility_user_secret_arns" {
  description = "Map of facility (FAC01/FAC02/FAC03) to the Secrets Manager ARN holding its demo db_user's password - only that facility's demo IAM role can read it."
  value       = { for user, facility in local.demo_facilities : facility => aws_secretsmanager_secret.demo_facility_user[user].arn }
}
