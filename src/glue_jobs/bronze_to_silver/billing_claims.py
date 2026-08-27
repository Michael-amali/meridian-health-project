"""Bronze -> Silver cleansing job for the `billing_claims` source.

Validates one day of raw claims CSV against the closed payer/status sets and
a sane claim-amount range the generator uses
(src/generators/batch/billing_claims.py).
"""

from pyspark.sql.types import DoubleType, StringType, StructField, StructType

from common import read_raw_partition, resolved_args, run_cleansing_job, start_job

SCHEMA = StructType(
    [
        StructField("claim_id", StringType()),
        StructField("patient_id", StringType()),
        StructField("facility_id", StringType()),
        StructField("payer", StringType()),
        StructField("claim_amount", DoubleType()),
        StructField("status", StringType()),
        StructField("service_date", StringType()),
    ]
)

RULESET = """
    Rules = [
        IsComplete "claim_id",
        IsComplete "patient_id",
        IsComplete "facility_id",
        IsComplete "claim_amount",
        Uniqueness "claim_id" > 0.99,
        ColumnValues "patient_id" matches "P[0-9]{5}",
        ColumnValues "facility_id" in ["FAC01", "FAC02", "FAC03"],
        ColumnValues "payer" in ["Medicare", "Medicaid", "BlueCross", "Aetna", "UnitedHealth", "SelfPay"],
        ColumnValues "status" in ["Submitted", "Paid", "Denied", "Pending"],
        ColumnValues "claim_amount" between 0 and 100000
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
