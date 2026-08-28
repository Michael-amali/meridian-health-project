"""Bronze -> Silver cleansing job for the `patients` reference source.

Validates the static patient master seed (src/generators/reference/
generate_seed_files.py) the same way any daily source is validated - this
just happens to run against one fixed dt= partition instead of a new one
each day (see local.reference_dt in terraform/modules/bronze-to-silver/
main.tf). Phase 4's dim_patient job reads the cleansed output of this job.
"""

from pyspark.sql.types import StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("patient_id", StringType()),
        StructField("full_name", StringType()),
        StructField("date_of_birth", StringType()),
        StructField("phone", StringType()),
        StructField("government_id", StringType()),
    ]
)

RULESET = """
    Rules = [
        IsComplete "patient_id",
        IsComplete "full_name",
        IsComplete "date_of_birth",
        IsComplete "government_id",
        Uniqueness "patient_id" > 0.99,
        ColumnValues "patient_id" matches "P[0-9]{5}"
    ]
"""


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    raw_df = read_raw_partition(
        glue_context, args["RAW_BUCKET"], args["SOURCE"], args["RUN_DATE"], "csv", SCHEMA
    )
    run_cleansing_job(glue_context, job, args, raw_df, RULESET)


if __name__ == "__main__":
    main()
