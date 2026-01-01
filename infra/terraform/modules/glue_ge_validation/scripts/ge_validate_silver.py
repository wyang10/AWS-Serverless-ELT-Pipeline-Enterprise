import json
import sys
from datetime import datetime, timezone

import boto3
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext


def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _result_key(result_prefix: str, record_type: str, dt: str, run_id: str) -> str:
    prefix = result_prefix.strip("/")
    return f"{prefix}/{record_type}/dt={dt}/run_{run_id}.json"


def _run_expectations(record_type: str, df):
    try:
        import great_expectations as ge  # type: ignore
    except Exception as e:
        raise RuntimeError(
            "great_expectations import failed. Ensure Glue job uses --additional-python-modules "
            "e.g. great-expectations==0.18.21. Error: " + str(e)
        ) from e

    dataset = ge.dataset.SparkDFDataset(df)
    results = []

    def add(res):
        results.append(res.to_json_dict())

    add(dataset.expect_table_row_count_to_be_between(1, None))

    if record_type == "shipments":
        add(dataset.expect_column_values_to_not_be_null("shipment_id"))
        add(dataset.expect_column_values_to_be_unique("shipment_id"))
        add(dataset.expect_column_values_to_not_be_null("event_time"))
        add(dataset.expect_column_values_to_be_between("weight_kg", 0, 200))
    elif record_type == "tracking_events":
        add(dataset.expect_column_values_to_not_be_null("shipment_id"))
        add(dataset.expect_column_values_to_not_be_null("event_time"))
        add(dataset.expect_column_values_to_not_be_null("status"))
    elif record_type == "invoice_lines":
        add(dataset.expect_column_values_to_not_be_null("invoice_id"))
        add(dataset.expect_column_values_to_not_be_null("event_time"))
        add(dataset.expect_column_values_to_be_between("quantity", 1, 1000))
        add(dataset.expect_column_values_to_be_between("unit_price", 0, 100000))
    else:
        add(dataset.expect_column_values_to_not_be_null("record_type"))

    success = all(r.get("success") is True for r in results)
    return success, results


def main() -> int:
    args = getResolvedOptions(
        sys.argv,
        [
            "JOB_NAME",
            "SILVER_BUCKET",
            "SILVER_PREFIX",
            "RECORD_TYPE",
            "DT",
            "RESULT_PREFIX",
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
    result_prefix = args["RESULT_PREFIX"]

    src = f"s3://{silver_bucket}/{silver_prefix}/{record_type}/dt={dt}/"
    run_id = getattr(sc, "applicationId", "run")

    df = spark.read.parquet(src)
    success, expectation_results = _run_expectations(record_type, df)

    payload = {
        "success": success,
        "record_type": record_type,
        "dt": dt,
        "source": src,
        "run_id": run_id,
        "generated_at": _utc_now_iso(),
        "results": expectation_results,
    }

    s3 = boto3.client("s3")
    key = _result_key(result_prefix, record_type, dt, run_id)
    s3.put_object(
        Bucket=silver_bucket,
        Key=key,
        Body=json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8"),
        ContentType="application/json",
    )

    job.commit()
    if not success:
        print(json.dumps({"ok": False, "result_s3_key": key}))
        return 1

    print(json.dumps({"ok": True, "result_s3_key": key}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
