"""Curates fact_bed_occupancy from cleansed bed_capacity.

Grain: one row per facility/department/snapshot_date. Adds occupancy_rate,
the measure the operational dashboard's capacity-risk reporting needs.
"""

from pyspark.sql import functions as F

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    bed_capacity = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])

    fact_bed_occupancy = bed_capacity.withColumn(
        "occupancy_rate", F.col("occupied_beds") / F.col("total_beds")
    )

    write_curated_table(fact_bed_occupancy, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
