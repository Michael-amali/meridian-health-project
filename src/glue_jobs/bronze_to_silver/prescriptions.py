"""Bronze -> Silver cleansing job for the `prescriptions` streaming source.

Validates one day of raw prescription-issuance NDJSON (delivered by Kinesis
Firehose - see terraform/modules/kinesis-streaming) against the closed
facility set and a positive dosage the generator uses
(src/generators/streaming/common.py).
"""

from pyspark.sql.types import IntegerType, StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("event_id", StringType()),
        StructField("patient_id", StringType()),
        StructField("facility_id", StringType()),
        StructField("drug_name", StringType()),
        StructField("dosage_mg", IntegerType()),
        StructField("event_ts", StringType()),
    ]
)

RULESET = """
    Rules = [
        IsComplete "event_id",
        IsComplete "patient_id",
        IsComplete "facility_id",
        IsComplete "drug_name",
        ColumnValues "patient_id" matches "P[0-9]{5}",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "dosage_mg" > 0
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
