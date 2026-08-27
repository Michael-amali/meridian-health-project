# Two streaming domains - bedside vitals and prescription-issuance events -
# each get their own on-demand Kinesis stream and Firehose delivery stream to
# the raw bucket. Looped with for_each because the infrastructure shape is
# identical for both; the business data differs in the Python producer code
# (src/generators/streaming/), not here.
#
# Firehose lands data as newline-delimited JSON, not Parquet - the raw layer
# is meant to stay in its original format, and Parquet conversion needs a
# Glue Catalog table that doesn't exist until Phase 3.

locals {
  streams = toset(["vitals", "prescriptions"])
}

resource "aws_kinesis_stream" "this" {
  for_each = local.streams

  name = "meridian-${each.key}-stream-${var.env}"

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  encryption_type = "KMS"
  kms_key_id      = var.kms_key_arn

  tags = merge(var.tags, { Name = "meridian-${each.key}-stream-${var.env}" })
}

# --- Firehose: reads each stream and delivers it to S3 raw as JSON ---

resource "aws_iam_role" "firehose_delivery" {
  name = "meridian-firehose-delivery-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "firehose.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "firehose_delivery" {
  name = "firehose-delivery-access"
  role = aws_iam_role.firehose_delivery.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSourceStreams"
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetRecords",
          "kinesis:GetShardIterator",
          "kinesis:ListShards",
        ]
        Resource = [for stream in aws_kinesis_stream.this : stream.arn]
      },
      {
        Sid    = "WriteRawBucket"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject",
        ]
        Resource = [var.raw_bucket_arn, "${var.raw_bucket_arn}/*"]
      },
      {
        Sid    = "UseDataLakeKmsKey"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
        ]
        Resource = var.kms_key_arn
      },
      {
        Sid      = "WriteDeliveryLogs"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents"]
        Resource = [for log_group in aws_cloudwatch_log_group.firehose : "${log_group.arn}:*"]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "firehose" {
  for_each = local.streams

  name              = "/aws/kinesisfirehose/meridian-${each.key}-firehose-${var.env}"
  retention_in_days = 14

  tags = var.tags
}

resource "aws_cloudwatch_log_stream" "firehose" {
  for_each = local.streams

  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose[each.key].name
}

resource "aws_kinesis_firehose_delivery_stream" "this" {
  for_each = local.streams

  name        = "meridian-${each.key}-firehose-${var.env}"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.this[each.key].arn
    role_arn           = aws_iam_role.firehose_delivery.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_delivery.arn
    bucket_arn = var.raw_bucket_arn

    prefix              = "${each.key}/dt=!{timestamp:yyyy-MM-dd}/"
    error_output_prefix = "${each.key}-errors/dt=!{timestamp:yyyy-MM-dd}/!{firehose:error-output-type}/"

    # 60s / 1MiB buffer - capstone-scale volume means most files flush on the
    # time trigger, not the size one. Landing uncompressed JSON keeps the
    # files easy to eyeball while debugging Phase 3's crawler/cleanse jobs.
    buffering_size     = 1
    buffering_interval = 60

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose[each.key].name
      log_stream_name = aws_cloudwatch_log_stream.firehose[each.key].name
    }
  }

  tags = var.tags
}
