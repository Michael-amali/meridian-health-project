"""Curates dim_department - a small hardcoded lookup, not sourced from any
cleansed table. Every source only ever carries a bare department name
string, no separate ID, so department_id is synthesized here in list order.
Keep this list in sync with src/generators/batch/common.py's DEPARTMENTS
constant if a department is ever added/renamed.
"""

from common import resolved_args, start_job, write_curated_table

DEPARTMENTS = [
    ("DEPT01", "ER"),
    ("DEPT02", "ICU"),
    ("DEPT03", "Cardiology"),
    ("DEPT04", "Pediatrics"),
    ("DEPT05", "Orthopedics"),
]


def main():
    args = resolved_args()
    glue_context, job = start_job(args)
    spark = glue_context.spark_session

    dim_department = spark.createDataFrame(DEPARTMENTS, ["department_id", "department_name"])

    write_curated_table(dim_department, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
