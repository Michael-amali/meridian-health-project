# Baseline service roles that pipeline resources built in later phases
# (Glue jobs, Lambda generators) will assume. Each role only gets the
# permissions it needs today - later phases attach additional narrow policies
# (e.g. Kinesis access) rather than us guessing every future permission now.

locals {
  glue_layers      = ["raw", "cleansed", "curated", "scripts"]
  glue_bucket_arns = [for layer in local.glue_layers : var.bucket_arns[layer]]
  glue_object_arns = [for layer in local.glue_layers : "${var.bucket_arns[layer]}/*"]
}

# --- Glue service role: used by every Glue job/crawler in this project ---

resource "aws_iam_role" "glue_service" {
  name = "meridian-glue-service-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "glue.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

# AWS-managed policy covering the baseline permissions every Glue job needs
# (CloudWatch Logs, Glue Catalog access, etc.) so we don't have to hand-write
# that boilerplate ourselves.
resource "aws_iam_role_policy_attachment" "glue_service_managed" {
  role       = aws_iam_role.glue_service.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_data_lake_access" {
  name = "data-lake-access"
  role = aws_iam_role.glue_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListDataLakeBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = local.glue_bucket_arns
      },
      {
        Sid    = "ReadWriteDataLakeObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = local.glue_object_arns
      },
      {
        Sid    = "UseDataLakeKmsKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# --- Lambda execution role: used by the synthetic data generator functions ---

resource "aws_iam_role" "lambda_generator" {
  name = "meridian-lambda-generator-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_generator_managed" {
  role       = aws_iam_role.lambda_generator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Generators only ever write new files to the raw landing zone - they never
# need to read cleansed/curated data or delete anything.
resource "aws_iam_role_policy" "lambda_generator_raw_write" {
  name = "raw-bucket-write"
  role = aws_iam_role.lambda_generator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListRawBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.bucket_arns["raw"]
      },
      {
        Sid      = "WriteRawObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.bucket_arns["raw"]}/*"
      },
      {
        Sid    = "UseDataLakeKmsKeyForWrites"
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Generators also cover the streaming producer (src/generators/streaming/),
# which needs to push events onto both Kinesis streams alongside its existing
# raw-bucket write access.
resource "aws_iam_role_policy" "lambda_generator_kinesis_put" {
  name = "kinesis-put-records"
  role = aws_iam_role.lambda_generator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutStreamRecords"
        Effect   = "Allow"
        Action   = ["kinesis:PutRecord", "kinesis:PutRecords"]
        Resource = [for arn in var.stream_arns : arn]
      }
    ]
  })
}

# --- Lambda execution role: used by the vitals stream alerting consumer ---

resource "aws_iam_role" "lambda_alerting" {
  name = "meridian-lambda-alerting-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_alerting_managed" {
  role       = aws_iam_role.lambda_alerting.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# The alerting Lambda only ever reads the vitals stream (via its Kinesis
# event source mapping) and writes to the active-alerts table - it never
# touches the prescriptions stream or the data lake buckets.
resource "aws_iam_role_policy" "lambda_alerting_access" {
  name = "vitals-stream-and-alerts-table-access"
  role = aws_iam_role.lambda_alerting.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadVitalsStream"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
        ]
        Resource = var.vitals_stream_arn
      },
      {
        # The vitals stream is KMS-encrypted, so the event source mapping's
        # poller needs to decrypt records using this role before Lambda ever
        # sees them - without this, records fail to poll with a KMS access
        # error and the function is never invoked.
        Sid      = "DecryptVitalsStreamRecords"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = var.kms_key_arn
      },
      {
        Sid      = "WriteActiveAlerts"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.alerts_table_arn
      }
    ]
  })
}
