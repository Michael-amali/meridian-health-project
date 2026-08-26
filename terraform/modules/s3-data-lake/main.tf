# The data lake: five S3 buckets making up the bronze/silver/gold layers plus
# supporting buckets for pipeline code and access logs.
#
#   raw       (bronze) - immutable landing zone, original file formats
#   cleansed  (silver)  - validated/standardized/deduped Parquet
#   curated   (gold)   - dimensional model (facts/dims) ready for Redshift
#   scripts             - Glue job code, Lambda packages, DQ rule definitions
#   logs                - S3 server access logs for the four buckets above
#
# Bucket names must be globally unique across ALL of AWS, so every name is
# suffixed with the AWS account ID.

data "aws_caller_identity" "current" {}

locals {
  bucket_names = {
    raw      = "meridian-raw-${var.env}-${data.aws_caller_identity.current.account_id}"
    cleansed = "meridian-cleansed-${var.env}-${data.aws_caller_identity.current.account_id}"
    curated  = "meridian-curated-${var.env}-${data.aws_caller_identity.current.account_id}"
    scripts  = "meridian-scripts-${var.env}-${data.aws_caller_identity.current.account_id}"
    logs     = "meridian-logs-${var.env}-${data.aws_caller_identity.current.account_id}"
  }

  # The logs bucket receives access logs FROM the other four buckets, so it's
  # handled separately from them throughout this file.
  data_bucket_layers = ["raw", "cleansed", "curated", "scripts"]
}

# --- Bucket creation (identical shape for all five, so it's a single loop) ---

resource "aws_s3_bucket" "this" {
  for_each = local.bucket_names

  bucket = each.value

  tags = merge(var.tags, {
    Name  = each.value
    Layer = each.key
  })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Versioning is on everywhere except the logs bucket - log files are already
# an append-only stream, so versioning them just doubles storage cost for no
# benefit.
resource "aws_s3_bucket_versioning" "data_buckets" {
  for_each = toset(local.data_bucket_layers)

  bucket = aws_s3_bucket.this[each.key].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Every data bucket sends its access logs to the logs bucket, giving us the
# "who accessed what, when" audit trail the RFP's governance section asks for.
resource "aws_s3_bucket_logging" "data_buckets" {
  for_each = toset(local.data_bucket_layers)

  bucket = aws_s3_bucket.this[each.key].id

  target_bucket = aws_s3_bucket.this["logs"].id
  target_prefix = "${each.key}/"
}

# Reject any request that isn't over HTTPS - PHI must never travel in plaintext,
# even inside AWS's network.
resource "aws_s3_bucket_policy" "require_tls" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          each.value.arn,
          "${each.value.arn}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# --- Lifecycle rules (deliberately written out per bucket, not looped - each
# layer is kept for a different reason and at a different cost tier) ---

# Raw data is our source-of-truth backup of what arrived, but once it's been
# cleansed we rarely read it again. Move it to cheaper storage over time
# instead of paying Standard rates for data nobody queries.
resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.this["raw"].id

  rule {
    id     = "raw-tiered-storage"
    status = "Enabled"

    # Empty filter = apply to every object in the bucket.
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# Cleansed and curated data is queried more often (curated especially, since
# dashboards and Redshift loads read it), so it stays in Standard-IA rather
# than Glacier - still cheaper than Standard, without a retrieval delay.
resource "aws_s3_bucket_lifecycle_configuration" "cleansed" {
  bucket = aws_s3_bucket.this["cleansed"].id

  rule {
    id     = "cleansed-tiered-storage"
    status = "Enabled"

    filter {}

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "curated" {
  bucket = aws_s3_bucket.this["curated"].id

  rule {
    id     = "curated-tiered-storage"
    status = "Enabled"

    filter {}

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 60
    }
  }
}

# Access logs only need to exist long enough to investigate an incident.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.this["logs"].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}
