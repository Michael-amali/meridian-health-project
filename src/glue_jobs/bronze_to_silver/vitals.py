"""Bronze -> Silver cleansing job for the `vitals` streaming source.

Validates one day of raw vitals NDJSON (delivered by Kinesis Firehose - see
terraform/modules/kinesis-streaming) against physically-plausible ranges, not
the tighter clinical danger thresholds the stream_alerting Lambda already
checks in near-real-time - this gate is about catching corrupt/malformed
readings, not re-implementing clinical alerting.
"""

from pyspark.sql.types import DoubleType, StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("event_id", StringType()),
        StructField("patient_id", StringType()),
        StructField("facility_id", StringType()),
        StructField("heart_rate", DoubleType()),
        StructField("spo2", DoubleType()),
        StructField("systolic_bp", DoubleType()),
        StructField("diastolic_bp", DoubleType()),
        StructField("temperature_c", DoubleType()),
        StructField("event_ts", StringType()),
    ]
)

RULESET = """
    Rules = [
        IsComplete "event_id",
        IsComplete "patient_id",
        IsComplete "facility_id",
        ColumnValues "patient_id" matches "P[0-9]{5}",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "heart_rate" between 0 and 300,
        ColumnValues "spo2" between 0 and 100,
        ColumnValues "systolic_bp" between 0 and 300,
        ColumnValues "diastolic_bp" between 0 and 200,
        ColumnValues "temperature_c" between 20 and 45
    ]
"""


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    raw_df = read_raw_partition(
        glue_context, args["RAW_BUCKET"], args["SOURCE"], args["RUN_DATE"], "json", SCHEMA
    )
    run_cleansing_job(glue_context, job, args, raw_df, RULESET)


if __name__ == "__main__":
    main()
