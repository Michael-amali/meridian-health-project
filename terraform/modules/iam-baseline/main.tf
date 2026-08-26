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
