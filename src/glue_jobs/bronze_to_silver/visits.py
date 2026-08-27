"""Bronze -> Silver cleansing job for the `visits` source.

Validates one day of raw visit/admission CSV against the closed facility,
department, and visit-type sets the generator uses (src/generators/batch/
visits.py), then promotes it to cleansed Parquet only if every rule passes.
"""

from pyspark.sql.types import StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("visit_id", StringType()),
        StructField("patient_id", StringType()),
        StructField("facility_id", StringType()),
        StructField("department", StringType()),
        StructField("visit_type", StringType()),
        StructField("attending_staff_id", StringType()),
        StructField("admission_ts", StringType()),
        StructField("discharge_ts", StringType()),
    ]
)

# discharge_ts is deliberately left out of IsComplete - a still-admitted
# patient has no discharge time yet, and that's expected, not a DQ failure.
RULESET = """
    Rules = [
        IsComplete "visit_id",
        IsComplete "patient_id",
        IsComplete "facility_id",
        IsComplete "attending_staff_id",
        IsComplete "admission_ts",
        Uniqueness "visit_id" > 0.99,
        ColumnValues "patient_id" matches "P[0-9]{5}",
        ColumnValues "attending_staff_id" matches "S[0-9]{4}",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "department" in ["ER", "ICU", "Cardiology", "Pediatrics", "Orthopedics"],
        ColumnValues "visit_type" in ["Emergency", "Inpatient", "Outpatient"]
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
