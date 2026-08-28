"""Curates dim_payer - distinct payer values from cleansed billing_claims.

payer is a small closed set (see the PAYERS list in
src/generators/batch/billing_claims.py), so it's used directly as this
table's key rather than adding a surrogate integer key.
"""

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    billing_claims = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])
    dim_payer = billing_claims.select("payer").distinct()

    write_curated_table(dim_payer, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
