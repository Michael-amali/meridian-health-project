"""Curates dim_facility - a small hardcoded lookup, not sourced from any
cleansed table. facility_name never appears in any raw/cleansed source (only
facility_id does) - it only lives in src/generators/batch/common.py's
FACILITIES constant, so it's duplicated here. Keep this list in sync with
that one if a facility is ever added/renamed.
"""

from common import resolved_args, start_job, write_curated_table

FACILITIES = [
    ("FAC01", "Meridian General - Springfield"),
    ("FAC02", "Meridian North - Rivertown"),
    ("FAC03", "Meridian West - Lakeside"),
]


def main():
    args = resolved_args()
    glue_context, job = start_job(args)
    spark = glue_context.spark_session

    dim_facility = spark.createDataFrame(FACILITIES, ["facility_id", "facility_name"])

    write_curated_table(dim_facility, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
