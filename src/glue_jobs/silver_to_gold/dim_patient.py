"""Curates dim_patient from the cleansed `patients` reference source.

This table is Terraform-defined (not crawled) rather than picked up by the
curated crawler like most other tables in this module - see
terraform/modules/silver-to-gold/main.tf - specifically so its PII columns
(full_name, date_of_birth, phone, government_id) can carry an explicit
classification=pii tag that Lake Formation's column-exclusion grants key off
of (terraform/modules/lake-formation-grants).
"""

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    dim_patient = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])

    write_curated_table(dim_patient, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
