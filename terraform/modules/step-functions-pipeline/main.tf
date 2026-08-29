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

  # One branch per table to load - same "static Parallel, not a dynamic Map"
  # reasoning as cleanse_branches/curate_branches above (the table list is
  # fixed at apply time). TRUNCATE + COPY mirrors modules/redshift-warehouse's
  # own initial_load statement - see that module's schema.tf for why this is
  # a full-refresh overwrite, not an append.
  #
  # Unlike glue:startJobRun.sync/.sync used elsewhere in this module, the
  # Redshift Data API has no native ".sync" integration in Step Functions
  # (confirmed by testing: Step Functions rejects
  # "aws-sdk:redshiftdata:batchExecuteStatement.sync" as an unrecognized
  # resource - Redshift Data API just isn't one of the services Step
  # Functions natively waits on). BatchExecuteStatement itself only submits
  # the SQL and returns immediately, so each branch is its own
  # submit -> wait -> poll -> branch loop instead of a single Task.
  #
  # Authenticates via the Redshift admin secret (SecretArn), not this role's
  # own IAM identity - confirmed by testing that the "temporary credentials"
  # mode (WorkgroupName/Database with no SecretArn) requires the caller to
  # separately hold redshift-serverless:GetCredentials, and even then only
  # authenticates as an implicit IAM-mapped database user with no privileges
  # of its own on any table. Using the same admin secret every other
  # Terraform-managed statement in modules/redshift-warehouse already uses
  # avoids standing up and granting a whole separate native Redshift
  # identity just for this pipeline.
  redshift_branches = [
    for table in var.redshift_tables_to_load : {
      StartAt = "Load${table}Submit"
      States = {
        "Load${table}Submit" = {
          Type     = "Task"
          Resource = "arn:aws:states:::aws-sdk:redshiftdata:batchExecuteStatement"
          Parameters = {
            WorkgroupName = var.redshift_workgroup_name
            Database      = var.redshift_database_name
            SecretArn     = var.redshift_admin_secret_arn
            Sqls = [
              "TRUNCATE TABLE ${table}",
              "COPY ${table} FROM 's3://${var.curated_bucket_name}/${table}/' IAM_ROLE '${var.redshift_service_role_arn}' FORMAT AS PARQUET",
            ]
          }
          ResultPath = "$.submitted"
          Retry = [{
            ErrorEquals     = ["States.ALL"]
            IntervalSeconds = 30
            MaxAttempts     = 2
            BackoffRate     = 2.0
          }]
          Next = "Load${table}Wait"
        }
        "Load${table}Wait" = {
          Type    = "Wait"
          Seconds = 10
          Next    = "Load${table}Describe"
        }
        "Load${table}Describe" = {
          Type       = "Task"
          Resource   = "arn:aws:states:::aws-sdk:redshiftdata:describeStatement"
          Parameters = { "Id.$" = "$.submitted.Id" }
          ResultPath = "$.status"
          Next       = "Load${table}Choice"
        }
        "Load${table}Choice" = {
          Type = "Choice"
          Choices = [
            {
              Variable     = "$.status.Status"
              StringEquals = "FINISHED"
              Next         = "Load${table}Done"
            },
            {
              Or = [
                { Variable = "$.status.Status", StringEquals = "FAILED" },
                { Variable = "$.status.Status", StringEquals = "ABORTED" },
              ]
              Next = "Load${table}Failed"
            }
          ]
          # Anything else (SUBMITTED/PICKED/STARTED) means still running -
          # go back and wait some more.
          Default = "Load${table}Wait"
        }
        "Load${table}Done" = {
          Type = "Pass"
          End  = true
        }
        # A Fail state ends this branch abnormally, which the enclosing
        # Parallel's Catch (see redshift_states below) picks up the same way
        # it would a thrown error from a Task.
        "Load${table}Failed" = {
          Type  = "Fail"
          Error = "RedshiftLoadFailed"
          Cause = "Load of ${table} into Redshift failed or was aborted."
        }
      }
    }
  ]

  after_curate_next = length(var.redshift_tables_to_load) > 0 ? "LoadRedshift" : "NotifySuccess"

  # Same "for over an at-most-one-element list" trick as crawler_states above
  # - keeps this key fully absent (not a null state) when there's nothing to
  # load.
  redshift_states = {
    for _ in(length(var.redshift_tables_to_load) > 0 ? [true] : []) : "LoadRedshift" => {
      Type     = "Parallel"
      Branches = local.redshift_branches
      Catch = [{
        ErrorEquals = ["States.ALL"]
        ResultPath  = "$.error"
        Next        = "NotifyFailure"
      }]
      ResultPath = null
      Next       = "NotifySuccess"
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
      Next       = local.after_curate_next
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
    Comment = "Meridian ${var.name} pipeline: cleanse -> ${length(var.crawler_names) > 0 ? "refresh catalog -> " : ""}curate -> ${length(var.redshift_tables_to_load) > 0 ? "load redshift -> " : ""}notify."
    StartAt = "CleanseSources"
    States  = merge(local.base_states, local.crawler_states, local.redshift_states)
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
      }] : [],
      length(var.redshift_tables_to_load) > 0 ? [
        {
          Sid      = "RunRedshiftLoadStatements"
          Effect   = "Allow"
          Action   = ["redshift-data:BatchExecuteStatement"]
          Resource = var.redshift_workgroup_arn
        },
        {
          # DescribeStatement/GetStatementResult operate on a statement ID,
          # not a workgroup ARN - "*" is the only valid Resource shape for
          # these, same as cloudwatch:PutMetricData in modules/iam-baseline.
          Sid      = "PollRedshiftLoadStatements"
          Effect   = "Allow"
          Action   = ["redshift-data:DescribeStatement", "redshift-data:GetStatementResult"]
          Resource = "*"
        },
        {
          # BatchExecuteStatement authenticates via this secret (SecretArn
          # in Parameters above), not this role's own IAM identity - see the
          # redshift_branches local's header comment for why.
          Sid      = "ReadRedshiftAdminSecret"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = var.redshift_admin_secret_arn
        }
      ] : []
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
  state               = var.schedule_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  rule     = aws_cloudwatch_event_rule.schedule.name
  arn      = aws_sfn_state_machine.this.arn
  role_arn = aws_iam_role.eventbridge_invoke_sfn.arn
}
