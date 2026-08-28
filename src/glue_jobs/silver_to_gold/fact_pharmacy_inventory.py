"""Curates fact_pharmacy_inventory from cleansed pharmacy_inventory.

Grain: one row per facility/drug/snapshot_date. Adds stockout_risk, the flag
the operational dashboard's stockout-risk reporting needs.
"""

from pyspark.sql import functions as F

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    pharmacy_inventory = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])

    fact_pharmacy_inventory = pharmacy_inventory.withColumn(
        "stockout_risk", F.col("current_stock") <= F.col("reorder_threshold")
    )

    write_curated_table(fact_pharmacy_inventory, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
