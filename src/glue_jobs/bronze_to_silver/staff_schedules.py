"""Bronze -> Silver cleansing job for the `staff_schedules` source.

Validates one day of raw shift-roster CSV against the closed facility,
department, role, and shift-name sets the generator uses
(src/generators/batch/staff_schedules.py).
"""

from pyspark.sql.types import StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("staff_id", StringType()),
        StructField("facility_id", StringType()),
        StructField("department", StringType()),
        StructField("role", StringType()),
        StructField("shift_date", StringType()),
        StructField("shift_name", StringType()),
        StructField("shift_start", StringType()),
        StructField("shift_end", StringType()),
    ]
)

RULESET = """
    Rules = [
        IsComplete "staff_id",
        IsComplete "facility_id",
        IsComplete "shift_date",
        ColumnValues "staff_id" matches "S[0-9]{4}",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "department" in ["ER", "ICU", "Cardiology", "Pediatrics", "Orthopedics"],
        ColumnValues "role" in ["Nurse", "Physician", "Technician"],
        ColumnValues "shift_name" in ["Day", "Evening", "Night"]
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
