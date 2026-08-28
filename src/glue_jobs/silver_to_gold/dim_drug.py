"""Curates dim_drug - distinct drug_name values from cleansed
pharmacy_inventory.

drug_name is a small closed set (see the DRUGS list in
src/generators/batch/pharmacy_inventory.py), so it's used directly as this
table's key rather than adding a surrogate integer key.
"""

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    pharmacy_inventory = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])
    dim_drug = pharmacy_inventory.select("drug_name").distinct()

    write_curated_table(dim_drug, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
