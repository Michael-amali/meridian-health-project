"""Curates dim_date - a generated calendar lookup, not sourced from any
cleansed table. Covers every date this project's synthetic data could
plausibly touch: the fixed reference-data partition (2025-01-01) through
comfortable headroom into the future.
"""

from pyspark.sql import functions as F

from common import resolved_args, start_job, write_curated_table

START_DATE = "2025-01-01"
END_DATE = "2027-12-31"


def main():
    args = resolved_args()
    glue_context, job = start_job(args)
    spark = glue_context.spark_session

    date_range = spark.createDataFrame([(START_DATE, END_DATE)], ["start_date", "end_date"])
    dim_date = (
        date_range.select(
            F.explode(
                F.sequence(F.to_date("start_date"), F.to_date("end_date"), F.expr("interval 1 day"))
            ).alias("full_date")
        )
        .withColumn("date_key", F.date_format("full_date", "yyyy-MM-dd"))
        .withColumn("year", F.year("full_date"))
        .withColumn("quarter", F.quarter("full_date"))
        .withColumn("month", F.month("full_date"))
        .withColumn("month_name", F.date_format("full_date", "MMMM"))
        .withColumn("day_of_month", F.dayofmonth("full_date"))
        .withColumn("day_of_week", F.dayofweek("full_date"))
        .withColumn("day_name", F.date_format("full_date", "EEEE"))
        .withColumn("week_of_year", F.weekofyear("full_date"))
        .withColumn("is_weekend", F.dayofweek("full_date").isin(1, 7))
    )

    write_curated_table(dim_date, args["CURATED_BUCKET"], args["TABLE"])
    job.commit()


if __name__ == "__main__":
    main()
