"""Curates fact_staffing from cleansed staff_schedules.

Grain: one row per staff member per shift per day - carried through
unchanged, no computed measures called for by this table.
"""

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    fact_staffing = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])

    write_curated_table(fact_staffing, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
