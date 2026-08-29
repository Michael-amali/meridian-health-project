# Thin Lambda consumer on the vitals stream: flags dangerous readings into
# the active-alerts DynamoDB table (see src/lambdas/stream_alerting/handler.py).
# Deliberately does NOT touch the prescriptions stream - only vitals produce
# clinical danger alerts per the RFP.

module "alerting" {
  source = "../lambda-function"

  function_name = "meridian-stream-alerting-${var.env}"
  source_dir    = "${path.module}/../../../src/lambdas/stream_alerting"
  handler       = "handler.handler"
  role_arn      = var.lambda_role_arn

  environment_variables = {
    ALERTS_TABLE_NAME = var.alerts_table_name
  }

  tags = var.tags
}

resource "aws_lambda_event_source_mapping" "vitals_stream" {
  event_source_arn  = var.vitals_stream_arn
  function_name     = module.alerting.function_name
  starting_position = "LATEST"
  batch_size        = 10
  enabled           = var.consumer_enabled
}
