# Five daily batch generators (visits, staff schedules, billing claims,
# pharmacy inventory, bed capacity). Looped with for_each because the
# infrastructure shape - one Lambda + one daily schedule - is identical
# across all five; the differentiated business logic lives in the Python
# files under src/generators/batch/, not here. Schedules are staggered five
# minutes apart purely so their CloudWatch Log streams don't interleave.
#
# All five functions share one source directory (src/generators/batch), so
# every function's zip includes all five handler files plus common.py. That's
# a little wasteful but keeps this module simple - the alternative is
# per-function source directories that just re-import a shared module anyway.

locals {
  source_dir = "${path.module}/../../../src/generators/batch"

  sources = {
    visits             = { handler = "visits.handler", schedule = "cron(0 6 * * ? *)" }
    staff_schedules    = { handler = "staff_schedules.handler", schedule = "cron(5 6 * * ? *)" }
    billing_claims     = { handler = "billing_claims.handler", schedule = "cron(10 6 * * ? *)" }
    pharmacy_inventory = { handler = "pharmacy_inventory.handler", schedule = "cron(15 6 * * ? *)" }
    bed_capacity       = { handler = "bed_capacity.handler", schedule = "cron(20 6 * * ? *)" }
  }
}

module "generator" {
  source = "../lambda-function"

  for_each = local.sources

  function_name = "meridian-gen-${each.key}-${var.env}"
  source_dir    = local.source_dir
  handler       = each.value.handler
  role_arn      = var.lambda_role_arn

  environment_variables = {
    RAW_BUCKET_NAME = var.raw_bucket_name
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "schedule" {
  for_each = local.sources

  name                = "meridian-gen-${each.key}-schedule-${var.env}"
  schedule_expression = each.value.schedule
  state               = var.schedules_enabled ? "ENABLED" : "DISABLED"

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  for_each = local.sources

  rule = aws_cloudwatch_event_rule.schedule[each.key].name
  arn  = module.generator[each.key].function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  for_each = local.sources

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.generator[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule[each.key].arn
}
