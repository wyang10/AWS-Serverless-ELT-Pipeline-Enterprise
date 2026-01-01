from typing import Any, Dict, List, Optional

import boto3

from lambdas.shared.schemas import normalize_record
from lambdas.shared.utils import env, iter_json_records, json_dumps, log, parse_s3_event_records, utc_epoch


def _clients():
    return (
        boto3.client("s3"),
        boto3.client("sqs"),
        boto3.client("dynamodb"),
    )


def _acquire_object_lock(ddb, table_name: str, pk: str, lock_seconds: int) -> bool:
    now = utc_epoch()
    exp = now + lock_seconds
    try:
        ddb.update_item(
            TableName=table_name,
            Key={"pk": {"S": pk}},
            UpdateExpression="SET #s=:inflight, expires_at=:exp, updated_at=:now ADD attempts :one",
            ConditionExpression=(
                "attribute_not_exists(pk) "
                "OR (#s <> :processed AND (attribute_not_exists(expires_at) OR expires_at < :now))"
            ),
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":inflight": {"S": "INFLIGHT"},
                ":processed": {"S": "PROCESSED"},
                ":exp": {"N": str(exp)},
                ":now": {"N": str(now)},
                ":one": {"N": "1"},
            },
        )
        return True
    except ddb.exceptions.ConditionalCheckFailedException:
        return False


def _mark_processed(ddb, table_name: str, pk: str) -> None:
    now = utc_epoch()
    ddb.update_item(
        TableName=table_name,
        Key={"pk": {"S": pk}},
        UpdateExpression="SET #s=:processed, updated_at=:now REMOVE expires_at",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={":processed": {"S": "PROCESSED"}, ":now": {"N": str(now)}},
    )


def _mark_error(ddb, table_name: str, pk: str, reason: str) -> None:
    now = utc_epoch()
    ddb.update_item(
        TableName=table_name,
        Key={"pk": {"S": pk}},
        UpdateExpression="SET #s=:error, error_reason=:r, expires_at=:past, updated_at=:now",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":error": {"S": "ERROR"},
            ":r": {"S": reason[:500]},
            ":past": {"N": str(now - 1)},
            ":now": {"N": str(now)},
        },
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


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    queue_url = env("QUEUE_URL")
    table_name = env("IDEMPOTENCY_TABLE")
    lock_seconds = int(env("LOCK_SECONDS", "900"))

    s3, sqs, ddb = _clients()
    objects = parse_s3_event_records(event)
    total_records = 0
    total_enqueued = 0
    skipped = 0

    log("ingest_start", objects=len(objects))
    for bucket, key, etag in objects:
        pk = _object_id(bucket, key, etag)
        if not _acquire_object_lock(ddb, table_name, pk, lock_seconds=lock_seconds):
            skipped += 1
            log("ingest_skip_idempotent", pk=pk)
            continue

        try:
            text = _read_s3_text(s3, bucket, key)
            records: List[Dict[str, Any]] = []
            for line_no, obj in enumerate(iter_json_records(text), start=1):
                try:
                    normalized = normalize_record(obj)
                except Exception as e:
                    log("ingest_drop_bad_record", pk=pk, line_no=line_no, error=str(e))
                    continue
                normalized["_source"] = {"bucket": bucket, "key": key, "etag": etag, "line_no": line_no}
                records.append(normalized)

            total_records += len(records)
            enq = _enqueue_records(sqs, queue_url, records)
            total_enqueued += enq
            _mark_processed(ddb, table_name, pk)
            log("ingest_object_done", pk=pk, records=len(records), enqueued=enq)
        except Exception as e:
            _mark_error(ddb, table_name, pk, reason=str(e))
            log("ingest_object_error", pk=pk, error=str(e))
            raise

    return {
        "objects": len(objects),
        "records": total_records,
        "enqueued": total_enqueued,
        "skipped": skipped,
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
