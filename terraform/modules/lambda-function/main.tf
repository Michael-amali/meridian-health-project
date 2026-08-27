# Generic Lambda function: zip a source directory, create the function and
# its log group. Reused by batch-generators, streaming-producer, and
# streaming-alerts so the ~20 lines of zip/function/log-group boilerplate
# only exists once.
#
# Every function only needs boto3 (built into the Lambda Python runtime) and
# stdlib, so there's no pip install step - we just zip the source directory
# as-is.

data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/build/${var.function_name}.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_lambda_function" "this" {
  function_name = var.function_name
  role          = var.role_arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size

  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.this]

  tags = var.tags
}
