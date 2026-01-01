import io
import json
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple

import boto3

from lambdas.shared.schemas import normalize_record, partition_dt, to_pyarrow_schema
from lambdas.shared.utils import chunked, env, json_dumps, log, new_id


def _clients():
    return boto3.client("s3")


def _s3_put_parquet(s3, bucket: str, key: str, records: List[Dict[str, Any]], record_type: str) -> None:
    import pyarrow as pa  # type: ignore
    import pyarrow.parquet as pq  # type: ignore

    schema = to_pyarrow_schema(record_type)
    table = pa.Table.from_pylist(records, schema=schema)
    buf = io.BytesIO()
    pq.write_table(table, buf, compression="snappy")
    s3.put_object(Bucket=bucket, Key=key, Body=buf.getvalue())


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    out_bucket = env("SILVER_BUCKET")
    base_prefix = env("SILVER_PREFIX", "silver")
    max_records_per_file = int(env("MAX_RECORDS_PER_FILE", "5000"))
    emit_quality_events = env("QUALITY_EVENTBRIDGE_ENABLED", "false").lower() == "true"
    quality_bus_name = env("QUALITY_EVENTBUS_NAME", "default")
    quality_source = env("QUALITY_EVENT_SOURCE", "serverless-elt.transform")
    quality_detail_type = env("QUALITY_EVENT_DETAIL_TYPE", "silver_partition_ready")

    s3 = _clients()
    events = boto3.client("events") if emit_quality_events else None
    records = event.get("Records", [])
    failures: List[Dict[str, str]] = []

    good: List[Tuple[str, Dict[str, Any], str]] = []
    for r in records:
        msg_id = r.get("messageId") or r.get("messageID") or ""
        try:
            body = json.loads(r["body"])
            normalized = normalize_record(body)
            record_type = normalized["record_type"]
            good.append((msg_id, normalized, record_type))
        except Exception as e:
            log("transform_bad_message", message_id=msg_id, error=str(e))
            if msg_id:
                failures.append({"itemIdentifier": msg_id})

    # Group by (record_type, dt)
    grouped: Dict[Tuple[str, str], List[Tuple[str, Dict[str, Any]]]] = {}
    for msg_id, rec, record_type in good:
        dt = partition_dt([rec])
        grouped.setdefault((record_type, dt), []).append((msg_id, rec))

    written_files = 0
    partitions_written: Dict[Tuple[str, str], int] = {}
    for (record_type, dt), items in grouped.items():
        for items_chunk in chunked(items, max_records_per_file):
            only_records = [r for _, r in items_chunk]
            key = f"{base_prefix}/{record_type}/dt={dt}/batch_{getattr(context, 'aws_request_id', 'local')}_{new_id()}.parquet"
            try:
                _s3_put_parquet(s3, out_bucket, key, only_records, record_type=record_type)
                written_files += 1
                partitions_written[(record_type, dt)] = partitions_written.get((record_type, dt), 0) + 1
                log("transform_write_ok", record_type=record_type, dt=dt, key=key, count=len(only_records))
            except Exception as e:
                log("transform_write_error", record_type=record_type, dt=dt, error=str(e))
                failures.extend({"itemIdentifier": msg_id} for msg_id, _ in items_chunk if msg_id)

    if events and partitions_written:
        try:
            now = datetime.now(timezone.utc)
            entries = []
            for (record_type, dt), files_written in partitions_written.items():
                detail = {
                    "silver_bucket": out_bucket,
                    "silver_prefix": base_prefix,
                    "record_type": record_type,
                    "dt": dt,
                    "files_written": files_written,
                }
                entries.append(
                    {
                        "Source": quality_source,
                        "DetailType": quality_detail_type,
                        "Detail": json.dumps(detail, separators=(",", ":")),
                        "EventBusName": quality_bus_name,
                        "Time": now,
                    }
                )

            failed = 0
            for chunk in chunked(entries, 10):
                resp = events.put_events(Entries=chunk)
                failed += int(resp.get("FailedEntryCount", 0))
            log("quality_events_emitted", entries=len(entries), failed=failed)
        except Exception as e:
            log("quality_events_emit_error", error=str(e))

    return {"batchItemFailures": failures}


def _main() -> int:
    import sys

    event = json.loads(sys.stdin.read())
    print(json_dumps(handler(event, context=None)))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
