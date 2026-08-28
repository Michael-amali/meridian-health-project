# Phase 5: one SNS topic every orchestrated pipeline (modules/step-functions-
# pipeline) and every CloudWatch alarm (modules/monitoring) publishes to.
# Kept as its own tiny module, the same size as modules/dynamodb-alerts,
# because both of those modules need this topic's ARN and neither of them
# can depend on the other - a shared module both can take as an input is the
# only way to hand it to both without a circular module dependency.

resource "aws_sns_topic" "pipeline_alerts" {
  name              = "meridian-pipeline-alerts-${var.env}"
  kms_master_key_id = var.kms_key_arn

  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
