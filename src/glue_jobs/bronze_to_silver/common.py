"""Shared read/quarantine/write mechanics for the Phase 3 cleansing jobs.

Every job in this package (visits.py, vitals.py, etc.) only defines its own
raw schema and DQDL ruleset, then calls run_cleansing_job() here to do the
actual work: read the day's raw partition, evaluate the ruleset row by row,
promote the rows that passed every rule to cleansed Parquet, and quarantine
the rows that didn't - so one bad record no longer blocks an entire day's
good data. Keeping this in one place means a change to this mechanics (e.g.
Phase 4 tightening it) only has to happen once.
"""

import sys
from datetime import datetime, timedelta, timezone

import boto3
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from awsgluedq.transforms import EvaluateDataQuality
from pyspark.context import SparkContext
from pyspark.sql import functions as F

_s3 = boto3.client("s3")

REQUIRED_ARGS = ["JOB_NAME", "RAW_BUCKET", "CLEANSED_BUCKET", "SOURCE"]


def resolved_args():
    """Job arguments. RUN_DATE is optional - getResolvedOptions treats every
    name passed to it as required, so it's only requested when actually
    present on the command line, and defaults to yesterday otherwise (when
    this job runs on a schedule in Phase 5, today's raw data may still be
    arriving, so yesterday is the last fully-landed partition)."""
    args = getResolvedOptions(sys.argv, REQUIRED_ARGS)

    if "--RUN_DATE" in sys.argv:
        args["RUN_DATE"] = getResolvedOptions(sys.argv, REQUIRED_ARGS + ["RUN_DATE"])["RUN_DATE"]
    else:
        yesterday = datetime.now(timezone.utc) - timedelta(days=1)
        args["RUN_DATE"] = yesterday.strftime("%Y-%m-%d")

    return args


def start_job(args):
    sc = SparkContext()
    glue_context = GlueContext(sc)
    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)
    return glue_context, job


def read_raw_partition(glue_context, bucket, source, run_date, file_format, schema):
    """Reads s3://<bucket>/<source>/dt=<run_date>/ with an explicit schema, so
    a column with an unexpected type (e.g. text in a numeric field) becomes
    null under Spark's PERMISSIVE parsing mode instead of silently changing
    the inferred type for the whole file - the DQ completeness rules below
    are what catches that null."""
    path = f"s3://{bucket}/{source}/dt={run_date}/"
    reader = glue_context.spark_session.read.schema(schema)

    if file_format == "csv":
        return reader.option("header", "true").option("nullValue", "").csv(path)
    return reader.json(path)


def _evaluate_quality(glue_context, dynamic_frame, ruleset):
    """Runs the ruleset and returns both the rule-level outcomes (one row per
    rule - was every "IsComplete facility_id" check across the whole file a
    Pass or a Fail) and the row-level outcomes (one row per input record,
    with an extra DataQualityEvaluationResult column of "Passed"/"Failed").

    Row-level attribution only applies to rules that are actually about a
    single row (IsComplete, ColumnValues, ...) - a dataset-level rule like
    Uniqueness or CustomSql still runs and shows up in the rule-level
    outcomes, but can't flag which specific row caused it to fail, so it
    never quarantines a row by itself.
    """
    dq_results = EvaluateDataQuality().process_rows(
        frame=dynamic_frame,
        ruleset=ruleset,
        publishing_options={
            "dataQualityEvaluationContext": "EvaluateDataQuality",
            "enableDataQualityCloudWatchMetrics": False,
            "enableDataQualityResultsPublishing": False,
        },
        additional_options={"performanceTuning.caching": "CACHE_INPUT"},
    )
    rule_outcomes_df = dq_results.select("ruleOutcomes").toDF()
    row_outcomes_df = dq_results.select("rowLevelOutcomes").toDF()
    return rule_outcomes_df, row_outcomes_df


def _write_dq_results(outcomes_df, cleansed_bucket, source, run_date):
    """Always records every rule's outcome, pass or fail - this is what makes
    the gate's decisions queryable in Athena (the dq_results table) instead of
    only visible in this job's own CloudWatch logs.

    source and run_date aren't written as data columns - they're already the
    S3 path's source=/dt= partition keys, and Athena would otherwise see two
    columns named "source" (the partition key and this one) and reject the
    table as having duplicate columns.
    """
    (
        outcomes_df.withColumn("evaluated_metrics", F.to_json("EvaluatedMetrics"))
        .selectExpr(
            "Rule as rule",
            "Outcome as outcome",
            "FailureReason as failure_reason",
            "evaluated_metrics",
        )
        .write.mode("overwrite")
        .parquet(f"s3://{cleansed_bucket}/_dq_results/source={source}/dt={run_date}/")
    )


def _delete_prefix(bucket, prefix):
    """Removes every object under a prefix, if any exist. Used to clear a
    stale quarantine partition before conditionally rewriting it - without
    this, re-running a date whose bad rows have since been fixed upstream
    would leave the old (now-wrong) quarantined rows sitting there forever,
    since skipping the write when there's nothing to quarantine also skips
    Spark's own overwrite-on-write behavior."""
    paginator = _s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        keys = [{"Key": obj["Key"]} for obj in page.get("Contents", [])]
        if keys:
            _s3.delete_objects(Bucket=bucket, Delete={"Objects": keys})


def run_cleansing_job(glue_context, job, args, raw_df, ruleset, extra_valid_predicate=None):
    """Evaluates the ruleset row by row: rows that pass are promoted to
    cleansed Parquet, rows that fail are quarantined instead - so one bad
    record no longer blocks the rest of a day's good data. Always writes the
    rule-level DQ outcomes too, and always succeeds; the quarantine counts
    (printed below, and queryable as a row count once quarantine is crawled)
    are the signal something needs attention, not a failed job run.

    extra_valid_predicate is an escape hatch for a rule DQDL can't attribute
    to a single row - e.g. a CustomSql cross-column check like bed_capacity's
    "occupied_beds <= total_beds" only returns a dataset-wide count, so Glue
    can't tell which row(s) caused it to fail and never quarantines any of
    them for it. Pass a function (DataFrame -> boolean Column) here for that
    case; it's ANDed with the DQDL row-level result to decide quarantine.
    """
    source = args["SOURCE"]
    run_date = args["RUN_DATE"]
    cleansed_bucket = args["CLEANSED_BUCKET"]

    dynamic_frame = DynamicFrame.fromDF(raw_df, glue_context, "raw_dynamic_frame")
    rule_outcomes_df, row_outcomes_df = _evaluate_quality(glue_context, dynamic_frame, ruleset)
    _write_dq_results(rule_outcomes_df, cleansed_bucket, source, run_date)

    is_valid = row_outcomes_df.DataQualityEvaluationResult == "Passed"
    if extra_valid_predicate is not None:
        is_valid = is_valid & extra_valid_predicate(row_outcomes_df)

    good_rows = row_outcomes_df.filter(is_valid).select(*raw_df.columns)
    bad_rows = row_outcomes_df.filter(~is_valid).select(*raw_df.columns)
    good_count = good_rows.count()
    bad_count = bad_rows.count()

    good_rows.write.mode("overwrite").parquet(f"s3://{cleansed_bucket}/{source}/dt={run_date}/")

    # Quarantine lives under one shared _quarantine/ folder, one subfolder per
    # source (mirroring the cleansed data itself) rather than a flat
    # _quarantine_<source> prefix - a single Glue table still can't represent
    # every source's different columns, so each source is crawled into its
    # own "quarantine_<source>" table by the dedicated quarantine crawler
    # (see modules/bronze-to-silver) rather than by folder name alone.
    quarantine_prefix = f"_quarantine/{source}/dt={run_date}/"
    _delete_prefix(cleansed_bucket, quarantine_prefix)
    if bad_count > 0:
        bad_rows.write.mode("overwrite").parquet(f"s3://{cleansed_bucket}/{quarantine_prefix}")

    print(f"{source} dt={run_date}: promoted {good_count} row(s), quarantined {bad_count} row(s)")
    job.commit()
