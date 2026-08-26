output "key_arn" {
  description = "ARN of the data lake KMS key."
  value       = aws_kms_key.data_lake.arn
}

output "key_id" {
  description = "ID of the data lake KMS key."
  value       = aws_kms_key.data_lake.key_id
}

output "alias_name" {
  description = "Alias of the data lake KMS key."
  value       = aws_kms_alias.data_lake.name
}
