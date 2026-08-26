# Phase 1 (Foundations): the KMS key, data lake buckets, and baseline service
# roles that every later phase builds on top of. Nothing here processes data
# yet - it just creates a safe, governed place for data to land.

module "kms" {
  source = "../../modules/kms"

  env = var.env
}

module "s3_data_lake" {
  source = "../../modules/s3-data-lake"

  env         = var.env
  kms_key_arn = module.kms.key_arn
}

module "iam_baseline" {
  source = "../../modules/iam-baseline"

  env         = var.env
  bucket_arns = module.s3_data_lake.bucket_arns
  kms_key_arn = module.kms.key_arn
}
