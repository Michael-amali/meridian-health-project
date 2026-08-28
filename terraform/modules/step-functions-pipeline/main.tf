# Phase 5: generic Step Functions pipeline - runs a set of cleanse Glue jobs
# in parallel, optionally fires off a catalog refresh, then runs a set of
# curate Glue jobs in parallel, and always notifies the SNS alerts topic with
# the outcome. Reused for both the batch-daily and streaming-curation
# pipelines (terraform/environments/dev/main.tf) - the infrastructure shape
# is identical, only which jobs/crawlers run, and how often, differs, which
# is exactly the "loop for identical shape, vary the business data" case per
# this project's code-style convention (see modules/glue-job for the same
# pattern one level down).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  glue_job_arns = [
    for job_name in concat(var.cleanse_job_names, var.curate_job_names) :
    "arn:aws:glue:${local.region}:${local.account_id}:job/${job_name}"
  ]
  crawler_arns = [
    for crawler_name in var.crawler_names :
    "arn:aws:glue:${local.region}:${local.account_id}:crawler/${crawler_name}"
  ]

  # One Parallel branch per job - the job list is fixed at apply time (not a
  # runtime input), so a static Parallel state (one branch per job) is
  # simpler here than a dynamic Map state. Each job gets its own Retry so a
  # single transient Glue failure (or a job someone stops mid-run) is
  # retried in place without re-running its siblings.
  cleanse_branches = [
    for job_name in var.cleanse_job_names : {
      StartAt = job_name
      States = {
        (job_name) = {
          Type       = "Task"
          Resource   = "arn:aws:states:::glue:startJobRun.sync"
          Parameters = { JobName = job_name }
          Retry = [{
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }]
          End = true
        }
      }
    }
  ]

  curate_branches = [
    for job_name in var.curate_job_names : {
      StartAt = job_name
      States = {
        (job_name) = {
          Type       = "Task"
          Resource   = "arn:aws:states:::glue:startJobRun.sync"
          Parameters = { JobName = job_name }
          Retry = [{
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }]
          End = true
        }
      }
    }
  ]

  after_cleanse_next = length(var.crawler_names) > 0 ? "RefreshCatalog" : "CurateTables"

  # Crawlers are fired but not waited on: every curate job reads straight
  # from S3 (see read_cleansed_source() in
  # src/glue_jobs/silver_to_gold/common.py), not through the Glue Catalog,
  # so pipeline correctness never depends on a crawl finishing first -
  # crawlers only keep Athena's view of the cleansed/quarantine layers
  # fresh for humans. Each branch catches its own failure (e.g. the crawler
  # is still running from a prior overlapping trigger) and turns it into a
  # no-op instead of failing the whole pipeline over a catalog-freshness
  # nicety.
  #
  # Built as a `for` over an at-most-one-element list, not a `? {} : {...}`
  # ternary - Terraform unifies the two shapes of a ternary's branches by
  # filling missing keys with null, which would leave a literal
  # `"RefreshCatalog": null` entry in the state machine's States map when
  # crawler_names is empty, and Step Functions rejects a null state
  # definition. Filtering a `for` expression down to zero elements instead
  # produces a genuinely empty map, so the key is fully absent.
  crawler_states = {
    for _ in(length(var.crawler_names) > 0 ? [true] : []) : "RefreshCatalog" => {
      Type = "Parallel"
      Branches = [
        for crawler_name in var.crawler_names : {
          StartAt = crawler_name
          States = {
            (crawler_name) = {
              Type       = "Task"
              Resource   = "arn:aws:states:::aws-sdk:glue:startCrawler"
              Parameters = { Name = crawler_name }
              Catch = [{
                ErrorEquals = ["States.ALL"]
                Next        = "${crawler_name}Ignored"
              }]
              End = true
            }
            "${crawler_name}Ignored" = {
              Type = "Pass"
              End  = true
            }
          }
        }
      ]
      ResultPath = null
      Next       = "CurateTables"
    }
  }

  base_states = {
    CleanseSources = {
      Type     = "Parallel"
      Branches = local.cleanse_branches
      Catch = [{
        ErrorEquals = ["States.ALL"]
        ResultPath  = "$.error"
        Next        = "NotifyFailure"
      }]
      ResultPath = null
      Next       = local.after_cleanse_next
    }
    CurateTables = {
      Type     = "Parallel"
      Branches = local.curate_branches
      Catch = [{
        ErrorEquals = ["States.ALL"]
        ResultPath  = "$.error"
        Next        = "NotifyFailure"
      }]
      ResultPath = null
      Next       = "NotifySuccess"
    }
    NotifySuccess = {
      Type     = "Task"
      Resource = "arn:aws:states:::sns:publish"
      Parameters = {
        TopicArn = var.sns_topic_arn
        Subject  = "Meridian ${var.name} pipeline succeeded (${var.env})"
        Message  = "The ${var.name} pipeline completed successfully."
      }
      Next = "Success"
    }
    NotifyFailure = {
      Type     = "Task"
      Resource = "arn:aws:states:::sns:publish"
      Parameters = {
        TopicArn    = var.sns_topic_arn
        Subject     = "Meridian ${var.name} pipeline FAILED (${var.env})"
        "Message.$" = "States.Format('The ${var.name} pipeline failed. Error: {} Cause: {}', $.error.Error, $.error.Cause)"
      }
      Next = "Failure"
    }
    Success = { Type = "Succeed" }
    Failure = { Type = "Fail" }
  }

  state_machine_definition = jsonencode({
    Comment = "Meridian ${var.name} pipeline: cleanse -> ${length(var.crawler_names) > 0 ? "refresh catalog -> " : ""}curate -> notify."
    StartAt = "CleanseSources"
    States  = merge(local.base_states, local.crawler_states)
  })
}

# --- Step Functions execution role ---

resource "aws_iam_role" "sfn_execution" {
  name = "meridian-sfn-${var.name}-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "sfn_execution" {
  name = "pipeline-access"
  role = aws_iam_role.sfn_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "RunAndMonitorGlueJobs"
          Effect   = "Allow"
          Action   = ["glue:StartJobRun", "glue:GetJobRun", "glue:GetJobRuns", "glue:BatchStopJobRun"]
          Resource = local.glue_job_arns
        },
        {
          # glue:startJobRun.sync doesn't long-poll the job itself - it works
          # by having EventBridge notify Step Functions through an
          # AWS-managed rule, so the execution role needs permission to
          # manage that specific rule (see
          # https://docs.aws.amazon.com/step-functions/latest/dg/connect-glue.html).
          Sid      = "ManageGlueSyncEventRule"
          Effect   = "Allow"
          Action   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
          Resource = "arn:aws:events:${local.region}:${local.account_id}:rule/StepFunctionsGetEventForGlueJobRunRule"
        },
        {
          Sid      = "PublishAlerts"
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = var.sns_topic_arn
        },
        {
          # The alerts topic is KMS-encrypted (see modules/sns-alerts), so
          # publishing to it needs a data key from this same key, not just
          # sns:Publish - confirmed by testing (SNS.KMSAccessDeniedException)
          # when this was missing, not by reading docs.
          Sid      = "DecryptAlertsTopic"
          Effect   = "Allow"
          Action   = ["kms:GenerateDataKey", "kms:Decrypt"]
          Resource = var.kms_key_arn
        }
      ],
      length(var.crawler_names) > 0 ? [{
        Sid      = "RunCrawlers"
        Effect   = "Allow"
        Action   = ["glue:StartCrawler"]
        Resource = local.crawler_arns
      }] : []
    )
  })
}

resource "aws_sfn_state_machine" "this" {
  name       = "meridian-sfn-${var.name}-${var.env}"
  role_arn   = aws_iam_role.sfn_execution.arn
  definition = local.state_machine_definition

  tags = var.tags
}

# --- EventBridge schedule that triggers this pipeline ---

resource "aws_iam_role" "eventbridge_invoke_sfn" {
  name = "meridian-eventbridge-sfn-${var.name}-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "eventbridge_invoke_sfn" {
  name = "start-execution"
  role = aws_iam_role.eventbridge_invoke_sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartPipelineExecution"
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = aws_sfn_state_machine.this.arn
    }]
  })
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "meridian-sfn-${var.name}-schedule-${var.env}"
  schedule_expression = var.schedule_expression

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_sfn_state_machine.this.arn
  role_arn = aws_iam_role.eventbridge_invoke_sfn.arn
}
