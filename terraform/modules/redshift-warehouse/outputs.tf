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

# --- Network + endpoint details, exposed for Phase 7's QuickSight VPC
# connection. QuickSight reaches this workgroup over a private ENI in these
# same subnets rather than over the internet, because the workgroup is
# publicly_accessible = false (see network.tf).

output "vpc_id" {
  description = "ID of the dedicated Redshift VPC - the QuickSight VPC connection places its ENIs in this same VPC."
  value       = aws_vpc.redshift.id
}

output "subnet_ids" {
  description = "The 3 private subnet IDs the workgroup runs in - reused for the QuickSight VPC connection's ENIs."
  value       = aws_subnet.redshift[*].id
}

output "security_group_id" {
  description = "Security group attached to the workgroup - Phase 7 adds an inbound 5439 rule to it for the QuickSight VPC connection's own security group."
  value       = aws_security_group.redshift.id
}

output "endpoint_address" {
  description = "Private DNS host name of the workgroup endpoint - the host QuickSight's Redshift data source connects to."
  value       = aws_redshiftserverless_workgroup.this.endpoint[0].address
}

output "endpoint_port" {
  description = "Port the workgroup endpoint listens on."
  value       = aws_redshiftserverless_workgroup.this.endpoint[0].port
}
