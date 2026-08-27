"""Bronze -> Silver cleansing job for the `pharmacy_inventory` source.

Validates one day of raw stock-snapshot CSV against the closed facility set
and non-negative stock/threshold values the generator uses
(src/generators/batch/pharmacy_inventory.py).
"""

from pyspark.sql.types import DoubleType, IntegerType, StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("facility_id", StringType()),
        StructField("drug_name", StringType()),
        StructField("current_stock", IntegerType()),
        StructField("reorder_threshold", IntegerType()),
        StructField("unit_cost", DoubleType()),
        StructField("snapshot_date", StringType()),
    ]
)

RULESET = """
    Rules = [
        IsComplete "facility_id",
        IsComplete "drug_name",
        IsComplete "current_stock",
        IsComplete "reorder_threshold",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "current_stock" >= 0,
        ColumnValues "reorder_threshold" >= 0,
        ColumnValues "unit_cost" between 0 and 10000
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
