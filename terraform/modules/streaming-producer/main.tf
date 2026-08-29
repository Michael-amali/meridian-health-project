# One Lambda, on a 1-minute schedule, that pushes a small batch of synthetic
# vitals + prescription-issuance events onto both Kinesis streams every run
# (see src/generators/streaming/producer.py).

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "meridian-streaming-producer-schedule-${var.env}"
  schedule_expression = "rate(5 hours)" # previously  rate(1 minute), adjusted for testing purposes
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

module "producer" {
  source = "../lambda-function"

  function_name = "meridian-streaming-producer-${var.env}"
  source_dir    = "${path.module}/../../../src/generators/streaming"
  handler       = "producer.handler"
  role_arn      = var.lambda_role_arn
  timeout       = 60

  environment_variables = {
    VITALS_STREAM_NAME        = var.vitals_stream_name
    PRESCRIPTIONS_STREAM_NAME = var.prescriptions_stream_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = module.producer.function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.producer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
