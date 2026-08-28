# Phase 6: the Redshift Serverless namespace (storage + encryption) and
# workgroup (compute), plus the IAM role Redshift itself uses to read
# curated S3 data during COPY - separate from Lake Formation, which only
# governs the Glue Catalog / Athena / Spectrum path, not native Redshift
# tables (see this module's README-equivalent note in schema.tf).

resource "aws_iam_role" "redshift_service" {
  name = "meridian-redshift-service-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "redshift.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "redshift_curated_read" {
  name = "curated-bucket-read"
  role = aws_iam_role.redshift_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListCuratedBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = var.curated_bucket_arn
      },
      {
        Sid      = "ReadCuratedObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${var.curated_bucket_arn}/*"
      },
      {
        Sid      = "DecryptCuratedObjects"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = var.kms_key_arn
      }
    ]
  })
}

resource "aws_redshiftserverless_namespace" "this" {
  namespace_name = "meridian-${var.env}"
  db_name        = "meridian"
  kms_key_id     = var.kms_key_arn

  default_iam_role_arn = aws_iam_role.redshift_service.arn
  iam_roles            = [aws_iam_role.redshift_service.arn]

  # Redshift manages the admin password itself (stored in Secrets Manager) -
  # every DDL/load/RLS-setup statement this module runs (schema.tf, rls.tf)
  # authenticates as this admin via that secret, rather than us inventing
  # and storing our own.
  manage_admin_password = true

  tags = var.tags
}

resource "aws_redshiftserverless_workgroup" "this" {
  namespace_name = aws_redshiftserverless_namespace.this.namespace_name
  workgroup_name = "meridian-${var.env}"

  base_capacity       = 8 # smallest RPU increment - capstone-scale data volumes
  publicly_accessible = false
  subnet_ids          = aws_subnet.redshift[*].id
  security_group_ids  = [aws_security_group.redshift.id]

  tags = var.tags
}
