import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F


def main() -> int:
    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "SILVER_BUCKET",
            "SILVER_PREFIX",
            "RECORD_TYPE",
            "DT",
            "OUTPUT_PREFIX",
        ],
    )

    sc = SparkContext.getOrCreate()
    glue_context = GlueContext(sc)
    spark = glue_context.spark_session

    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)

    silver_bucket = args["SILVER_BUCKET"]
    silver_prefix = args["SILVER_PREFIX"].strip("/")
    record_type = args["RECORD_TYPE"]
    dt = args["DT"]
    output_prefix = args["OUTPUT_PREFIX"].strip("/")

    src = f"s3://{silver_bucket}/{silver_prefix}/{record_type}/dt={dt}/"
    dst = f"s3://{silver_bucket}/{output_prefix}/{record_type}/dt={dt}/"

    df = spark.read.parquet(src)
    df = df.withColumn("_ingested_at", F.current_timestamp())

    df.repartition(1).write.mode("overwrite").parquet(dst)

    job.commit()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
