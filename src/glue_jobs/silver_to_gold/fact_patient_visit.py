"""Curates fact_patient_visit from cleansed visits.

Grain: one row per visit_id. Adds two measures computed from the raw
admission/discharge timestamps so the dashboards don't have to: still_admitted
(true when there's no discharge yet) and length_of_stay_hours (null while
still admitted).
"""

from pyspark.sql import functions as F

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    visits = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])

    fact_patient_visit = visits.withColumn(
        "still_admitted", F.col("discharge_ts").isNull()
    ).withColumn(
        "length_of_stay_hours",
        F.when(
            F.col("discharge_ts").isNotNull(),
            (
                F.unix_timestamp(F.col("discharge_ts").cast("timestamp"))
                - F.unix_timestamp(F.col("admission_ts").cast("timestamp"))
            )
            / 3600.0,
        ),
    )

    write_curated_table(fact_patient_visit, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
