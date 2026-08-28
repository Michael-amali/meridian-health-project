# Phase 5: CloudWatch visibility into the orchestrated pipelines - the RFP's
# "automated, monitored, recovers without manual data-fixing" success
# criterion needs something to actually look at and alert on, beyond Step
# Functions' own built-in retries. Covers the 3 signals the plan names
# explicitly: job failures, Kinesis iterator age, and DQ failures.

data "aws_region" "current" {}

# --- Alarm 1: a pipeline execution failed outright (both Retry attempts on
# some job were exhausted) ---

resource "aws_cloudwatch_metric_alarm" "pipeline_failed" {
  for_each = var.state_machine_arns

  alarm_name          = "meridian-pipeline-failed-${each.key}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = var.tags
}

# --- Alarm 2: a Kinesis consumer (Firehose or the alerting Lambda) is
# falling behind the stream ---

resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  for_each = var.kinesis_stream_names

  alarm_name          = "meridian-kinesis-iterator-age-${each.key}-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 300
  statistic           = "Maximum"
  threshold           = 300000 # 5 minutes, in milliseconds
  namespace           = "AWS/Kinesis"
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = each.value
  }

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

# --- Alarm 3: a cleansing job quarantined rows - see
# _publish_quarantine_metric() in src/glue_jobs/bronze_to_silver/common.py.
# No per-source dimension: every cleansing job publishes to the same metric
# name, so one Sum-based alarm catches a bad run anywhere in the pipeline
# instead of needing one alarm per source. ---

resource "aws_cloudwatch_metric_alarm" "data_quality_failures" {
  alarm_name          = "meridian-dq-quarantined-rows-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  period              = 3600
  statistic           = "Sum"
  threshold           = 0
  namespace           = "Meridian/DataQuality"
  metric_name         = "QuarantinedRows"
  treat_missing_data  = "notBreaching"

  alarm_actions = [var.sns_topic_arn]

  tags = var.tags
}

# --- One dashboard tying all three signals together ---

resource "aws_cloudwatch_dashboard" "pipeline" {
  dashboard_name = "meridian-pipeline-${var.env}"

  dashboard_body = jsonencode({
    widgets = concat(
      [
        for label, arn in var.state_machine_arns : {
          type   = "metric"
          width  = 12
          height = 6
          properties = {
            title  = "Step Functions: ${label}"
            region = data.aws_region.current.name
            metrics = [
              ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", arn, { stat = "Sum" }],
              ["AWS/States", "ExecutionsFailed", "StateMachineArn", arn, { stat = "Sum" }],
            ]
          }
        }
      ],
      [
        {
          type   = "metric"
          width  = 12
          height = 6
          properties = {
            title  = "Kinesis iterator age"
            region = data.aws_region.current.name
            metrics = [
              for key, stream_name in var.kinesis_stream_names :
              ["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", "StreamName", stream_name, { stat = "Maximum", label = key }]
            ]
          }
        },
        {
          type   = "metric"
          width  = 12
          height = 6
          properties = {
            title  = "Data quality: quarantined rows"
            region = data.aws_region.current.name
            metrics = [
              ["Meridian/DataQuality", "QuarantinedRows", { stat = "Sum" }]
            ]
          }
        }
      ]
    )
  })
}
