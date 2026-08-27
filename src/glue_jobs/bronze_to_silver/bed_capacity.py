"""Bronze -> Silver cleansing job for the `bed_capacity` source.

Validates one day of raw bed-capacity CSV against the closed facility and
department sets, plus the real business invariant that occupied beds can
never exceed total beds (src/generators/batch/bed_capacity.py).
"""

from pyspark.sql.types import IntegerType, StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("facility_id", StringType()),
        StructField("department", StringType()),
        StructField("total_beds", IntegerType()),
        StructField("occupied_beds", IntegerType()),
        StructField("snapshot_date", StringType()),
    ]
)

# The CustomSql rule below only reports how many rows total violated the
# invariant across the whole file - Glue can't attribute a CustomSql result
# back to individual rows, so it never quarantines anything on its own. It's
# kept purely so that count shows up in dq_results. _occupied_beds_within_capacity
# below is what actually decides which specific rows get quarantined for it.
RULESET = """
    Rules = [
        IsComplete "facility_id",
        IsComplete "department",
        IsComplete "total_beds",
        IsComplete "occupied_beds",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "department" in ["ER", "ICU", "Cardiology", "Pediatrics", "Orthopedics"],
        ColumnValues "total_beds" > 0,
        ColumnValues "occupied_beds" >= 0,
        CustomSql "select count(*) from primary where occupied_beds > total_beds" = 0
    ]
"""


def _occupied_beds_within_capacity(df):
    return df.occupied_beds <= df.total_beds


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    raw_df = read_raw_partition(
        glue_context, args["RAW_BUCKET"], args["SOURCE"], args["RUN_DATE"], "csv", SCHEMA
    )
    run_cleansing_job(
        glue_context, job, args, raw_df, RULESET, extra_valid_predicate=_occupied_beds_within_capacity
    )


if __name__ == "__main__":
    main()
