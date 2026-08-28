"""Curates fact_vitals_alert from cleansed vitals.

Filters down to only the readings that breach a clinical danger threshold -
the same thresholds src/lambdas/stream_alerting/handler.py already checks in
near-real-time for the DynamoDB active-alerts table, duplicated here (Glue
jobs don't import Lambda code - same convention src/generators/streaming/
common.py already follows for its own duplicated constants) so this table's
definition of "alert" never drifts from what the operational dashboard's
near-real-time alerts already mean. Keep both in sync if thresholds change.
"""

from pyspark.sql import functions as F

from common import read_cleansed_source, resolved_args, start_job, write_curated_table


def main():
    args = resolved_args()
    glue_context, job = start_job(args)

    vitals = read_cleansed_source(glue_context, args["CLEANSED_BUCKET"], args["SOURCE"])

    # Mirrors THRESHOLDS in src/lambdas/stream_alerting/handler.py exactly,
    # including the lack of a diastolic_bp check there. Built here, not at
    # module level, since F.col() needs an active SparkContext - start_job()
    # above is what creates one.
    heart_rate_breach = (F.col("heart_rate") < 40) | (F.col("heart_rate") > 150)
    spo2_breach = F.col("spo2") < 90
    systolic_bp_breach = (F.col("systolic_bp") < 70) | (F.col("systolic_bp") > 180)
    temperature_breach = (F.col("temperature_c") < 35.0) | (F.col("temperature_c") > 40.0)
    any_breach = heart_rate_breach | spo2_breach | systolic_bp_breach | temperature_breach

    fact_vitals_alert = (
        vitals.withColumn("heart_rate_breach", heart_rate_breach)
        .withColumn("spo2_breach", spo2_breach)
        .withColumn("systolic_bp_breach", systolic_bp_breach)
        .withColumn("temperature_breach", temperature_breach)
        .filter(any_breach)
    )

    write_curated_table(fact_vitals_alert, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
