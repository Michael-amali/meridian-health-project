# Customer-managed KMS key used to encrypt everything in the data lake (S3
# buckets, and later Redshift). Using our own key instead of the AWS-managed
# S3 key (aws/s3) is what lets us control and audit exactly which IAM roles
# are allowed to decrypt patient data.

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "data_lake" {
  description             = "Encrypts the Meridian ${var.env} data lake (raw/cleansed/curated) and related services"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  # This key policy deliberately does NOT list every service/role that can use
  # the key. It grants the account root full control, then delegates "who can
  # actually use this key" to regular IAM policies (see the iam-baseline
  # module). That way, adding a new service that needs encryption is a normal
  # IAM policy change, not a change to this key's policy.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "meridian-data-lake-key-${var.env}"
  })
}

resource "aws_kms_alias" "data_lake" {
  name          = "alias/meridian-data-lake-${var.env}"
  target_key_id = aws_kms_key.data_lake.key_id
}
