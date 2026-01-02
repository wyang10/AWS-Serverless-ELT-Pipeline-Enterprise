"""
Ingest Lambda (Bronze → SQS) with object-level idempotency.

Trigger:
- S3 ObjectCreated events for Bronze JSON/JSONL objects.

What it does:
- Uses DynamoDB as an idempotency store keyed by the S3 object identity (`bucket/key + etag`).
- Reads the object, parses JSONL/JSON, normalizes records, and publishes to SQS in batches.
- Emits structured logs + embedded metrics via AWS Lambda Powertools.

Environment variables:
- `QUEUE_URL` (required): Destination SQS queue URL.
- `IDEMPOTENCY_TABLE` (required): DynamoDB table name for object locks.
- `IDEMPOTENCY_TTL_SECONDS` (optional): TTL for idempotency records (default 30 days).
- `LOCK_SECONDS` (optional, legacy): Backward-compatible alias for `IDEMPOTENCY_TTL_SECONDS`.
"""

from typing import Any, Dict, List, Optional

import boto3

from aws_lambda_powertools import Logger, Metrics
from aws_lambda_powertools.metrics import MetricUnit
from aws_lambda_powertools.utilities.idempotency import DynamoDBPersistenceLayer, IdempotencyConfig, idempotent_function

from lambdas.shared.schemas import normalize_record
from lambdas.shared.utils import env, iter_json_records, json_dumps, parse_s3_event_records


logger = Logger(service="serverless-elt.ingest")
metrics = Metrics(namespace="ServerlessELT", service="ingest")


def _clients():
    return (
        boto3.client("s3"),
        boto3.client("sqs"),
        boto3.client("dynamodb"),
    )


def _object_id(bucket: str, key: str, etag: str) -> str:
    return f"s3://{bucket}/{key}#{etag}"


def _read_s3_text(s3, bucket: str, key: str) -> str:
    obj = s3.get_object(Bucket=bucket, Key=key)
    return obj["Body"].read().decode("utf-8")


def _enqueue_records(sqs, queue_url: str, records: List[Dict[str, Any]]) -> int:
    sent = 0
    entries: List[Dict[str, Any]] = []
    for i, r in enumerate(records):
        entries.append({"Id": str(i), "MessageBody": json_dumps(r)})
        if len(entries) == 10:
            resp = sqs.send_message_batch(QueueUrl=queue_url, Entries=entries)
            failed = resp.get("Failed", [])
            if failed:
                raise RuntimeError(f"sqs_send_failed={len(failed)} first={failed[0].get('Message')}")
            sent += len(entries)
            entries = []

    if entries:
        resp = sqs.send_message_batch(QueueUrl=queue_url, Entries=entries)
        failed = resp.get("Failed", [])
        if failed:
            raise RuntimeError(f"sqs_send_failed={len(failed)} first={failed[0].get('Message')}")
        sent += len(entries)
    return sent


def _log(event: str, **fields: Any) -> None:
    logger.info(event, extra=fields)


def _cached_response_hook(response: Any, data_record: Any) -> Any:
    if isinstance(response, dict):
        return {**response, "cached": True}
    return {"cached": True, "result": response}


def _get_idempotent_processor(table_name: str, ttl_seconds: int, ddb_client: Any, lambda_context: Any):
    config = IdempotencyConfig(
        event_key_jmespath="pk",
        expires_after_seconds=ttl_seconds,
        response_hook=_cached_response_hook,
        lambda_context=lambda_context,
    )
    persistence = DynamoDBPersistenceLayer(
        table_name=table_name,
        key_attr="pk",
        expiry_attr="expires_at",
        in_progress_expiry_attr="in_progress_expires_at",
        status_attr="status",
        data_attr="data",
        validation_key_attr="validation",
        boto3_client=ddb_client,
    )

    @idempotent_function(data_keyword_argument="item", persistence_store=persistence, config=config)
    def _process_object(*, item: Dict[str, Any], s3: Any, sqs: Any, queue_url: str) -> Dict[str, Any]:
        bucket = item["bucket"]
        key = item["key"]
        etag = item.get("etag", "")
        object_id = item["pk"]

        text = _read_s3_text(s3, bucket, key)
        records: List[Dict[str, Any]] = []
        dropped = 0
        for line_no, obj in enumerate(iter_json_records(text), start=1):
            try:
                normalized = normalize_record(obj)
            except Exception as e:
                dropped += 1
                _log("ingest_drop_bad_record", object_id=object_id, line_no=line_no, error=str(e))
                continue
            normalized["_source"] = {"bucket": bucket, "key": key, "etag": etag, "line_no": line_no}
            records.append(normalized)

        enq = _enqueue_records(sqs, queue_url, records)
        _log("ingest_object_done", object_id=object_id, records=len(records), enqueued=enq, dropped=dropped)
        return {"records": len(records), "enqueued": enq, "dropped": dropped}

    return _process_object


@metrics.log_metrics(capture_cold_start_metric=True)
def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    queue_url = env("QUEUE_URL")
    table_name = env("IDEMPOTENCY_TABLE")
    ttl_seconds = int(env("IDEMPOTENCY_TTL_SECONDS", env("LOCK_SECONDS", str(30 * 24 * 60 * 60))))

    s3, sqs, ddb = _clients()
    objects = parse_s3_event_records(event)
    total_records = 0
    total_enqueued = 0
    skipped = 0
    dropped = 0

    metrics.add_metric(name="ObjectsReceived", unit=MetricUnit.Count, value=len(objects))
    _log("ingest_start", objects=len(objects))

    lambda_context = context if hasattr(context, "get_remaining_time_in_millis") else None
    process_object = _get_idempotent_processor(table_name=table_name, ttl_seconds=ttl_seconds, ddb_client=ddb, lambda_context=lambda_context)
    for bucket, key, etag in objects:
        object_id = _object_id(bucket, key, etag)
        item = {"pk": object_id, "bucket": bucket, "key": key, "etag": etag}
        try:
            result = process_object(item=item, s3=s3, sqs=sqs, queue_url=queue_url)
        except Exception as e:
            _log("ingest_object_error", object_id=object_id, error=str(e))
            raise

        if isinstance(result, dict) and result.get("cached") is True:
            skipped += 1
            metrics.add_metric(name="ObjectsSkippedIdempotent", unit=MetricUnit.Count, value=1)
            _log("ingest_skip_idempotent", object_id=object_id)
            continue

        total_records += int(result.get("records", 0))
        total_enqueued += int(result.get("enqueued", 0))
        dropped += int(result.get("dropped", 0))

    metrics.add_metric(name="RecordsEnqueued", unit=MetricUnit.Count, value=total_enqueued)
    metrics.add_metric(name="RecordsParsed", unit=MetricUnit.Count, value=total_records)
    if dropped:
        metrics.add_metric(name="RecordsDropped", unit=MetricUnit.Count, value=dropped)
    if skipped:
        metrics.add_metric(name="ObjectsSkippedIdempotent", unit=MetricUnit.Count, value=skipped)

    return {
        "objects": len(objects),
        "records": total_records,
        "enqueued": total_enqueued,
        "skipped": skipped,
        "dropped": dropped,
        "request_id": getattr(context, "aws_request_id", None),
    }


# Local quick check (optional): `python -c 'import json; from lambdas.ingest.app import handler; ...'`
def _main() -> int:
    import sys

    event = json.loads(sys.stdin.read())
    print(json.dumps(handler(event, context=None), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
