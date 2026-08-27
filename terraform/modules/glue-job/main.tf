# Generic single Glue job: upload its script, then create the job resource.
# Reused by bronze-to-silver for each of the 7 cleansing jobs - the
# infrastructure shape is identical; each source's own DQ rules and schema
# live in its script, not here (same split as lambda-function vs.
# batch-generators).

resource "aws_s3_object" "script" {
  bucket = var.scripts_bucket
  key    = var.script_s3_key
  source = var.script_local_path

  # source_hash (not etag) - the scripts bucket uses SSE-KMS default
  # encryption, so S3 returns an encrypted ETag that never matches a plain
  # filemd5() of the script. source_hash is compared against its own last
  # value instead, so re-uploads are only triggered by real content changes.
  source_hash = filemd5(var.script_local_path)

  tags = var.tags
}

resource "aws_glue_job" "this" {
  name              = var.job_name
  role_arn          = var.role_arn
  glue_version      = var.glue_version
  worker_type       = var.worker_type
  number_of_workers = var.number_of_workers
  timeout           = var.timeout_minutes
  max_retries       = var.max_retries

  command {
    script_location = "s3://${var.scripts_bucket}/${aws_s3_object.script.key}"
    python_version  = "3"
  }

  default_arguments = merge(
    {
      "--enable-glue-datacatalog" = "true"
      "--enable-metrics"          = "true"
      "--job-language"            = "python"
    },
    var.default_arguments
  )

  tags = var.tags
}
