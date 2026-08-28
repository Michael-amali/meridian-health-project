"""Shared read/write mechanics for the Phase 4 curation jobs.

Every job in this package (dim_date.py, fact_claim.py, etc.) only defines its
own transformation logic, then calls read_cleansed_source() and
write_curated_table() here. Unlike Phase 3's cleansing jobs, there's no daily
partition and no DQ gate - Phase 3 already validated the inputs, and every
curated table here is a full rebuild each run (data volumes are tiny, so a
full overwrite is simpler than tracking incremental changes).
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

REQUIRED_ARGS = ["JOB_NAME", "CLEANSED_BUCKET", "CURATED_BUCKET", "TABLE"]


def resolved_args():
    """Job arguments. SOURCE is optional - dim_date, dim_facility, and
    dim_department have no cleansed input (they're generated or hardcoded),
    so it's only requested when actually present on the command line, same
    pattern as RUN_DATE in bronze_to_silver/common.py."""
    args = getResolvedOptions(sys.argv, REQUIRED_ARGS)

    if "--SOURCE" in sys.argv:
        args["SOURCE"] = getResolvedOptions(sys.argv, REQUIRED_ARGS + ["SOURCE"])["SOURCE"]

    return args


def start_job(args):
    sc = SparkContext()
    glue_context = GlueContext(sc)
    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)
    return glue_context, job


def read_cleansed_source(glue_context, cleansed_bucket, source):
    """Reads every dt= partition of a cleansed source at once - gold tables
    are full-refresh, so there's no single day to read. This goes straight to
    S3 rather than through the Glue Catalog (glue_context.create_dynamic_frame
    .from_catalog), the same directness Phase 3's read_raw_partition uses, so
    this job has no ordering dependency on the cleansed crawler having
    already picked up the latest partitions."""
    df = glue_context.spark_session.read.parquet(f"s3://{cleansed_bucket}/{source}/")
    return df.drop("dt") if "dt" in df.columns else df


def write_curated_table(df, curated_bucket, table):
    """Full overwrite, no partitioning - every curated table here is small
    enough that partitioning would only add directory-listing overhead."""
    df.write.mode("overwrite").parquet(f"s3://{curated_bucket}/{table}/")
