output "state_machine_arn" {
  description = "ARN of this pipeline's Step Functions state machine."
  value       = aws_sfn_state_machine.this.arn
}

output "state_machine_name" {
  description = "Name of this pipeline's Step Functions state machine."
  value       = aws_sfn_state_machine.this.name
}
