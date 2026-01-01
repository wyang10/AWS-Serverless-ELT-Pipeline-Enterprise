"""
Step Functions task: replay/backfill by copying S3 objects within the Bronze bucket.

Why copy instead of publishing to SQS directly?
- It reuses the normal S3 → ingest path (idempotency, parsing, retries).
- It can be run with limited IAM permissions (no need for `sqs:SendMessage`).

Inputs (from Step Functions execution input):
- `bronze_bucket` (required)
- `src_prefix` (required): source prefix to scan (e.g., "bronze/shipments/")
- `dest_prefix_base` (optional): must start with "bronze/" to trigger ingest
- `window_hours` (optional) OR explicit `start` / `end` (ISO-8601)
"""

from datetime import datetime, timedelta, timezone
from typing import Any, Dict

import boto3

from lambdas.shared.utils import log


def _parse_dt(s: str) -> datetime:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def _iso_z(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    s3 = boto3.client("s3")

    payload = event.get("input") if isinstance(event.get("input"), dict) else event

    bronze_bucket = payload["bronze_bucket"]
    src_prefix = payload["src_prefix"]
    dest_prefix_base = payload.get("dest_prefix_base", "bronze/replay")
    execution_name = event.get("execution_name") or payload.get("execution_name") or getattr(context, "aws_request_id", "run")

    start_s = payload.get("start")
    end_s = payload.get("end")
    window_hours = int(payload.get("window_hours", 24))
    now = datetime.now(timezone.utc)
    start = _parse_dt(start_s) if start_s else now - timedelta(hours=window_hours)
    end = _parse_dt(end_s) if end_s else now

    if not dest_prefix_base.startswith("bronze/"):
        raise ValueError("dest_prefix_base must start with 'bronze/' to trigger ingest")

    dest_prefix = dest_prefix_base.rstrip("/") + "/" + execution_name

    copied = 0
    scanned = 0

    log(
        "replay_start",
        bronze_bucket=bronze_bucket,
        src_prefix=src_prefix,
        dest_prefix=dest_prefix,
        start=_iso_z(start),
        end=_iso_z(end),
    )

    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=bronze_bucket, Prefix=src_prefix):
        for obj in page.get("Contents", []):
            scanned += 1
            last_modified = obj["LastModified"].astimezone(timezone.utc)
            if not (start <= last_modified <= end):
                continue

            # Copy to a new key under dest_prefix, so S3 notifications re-trigger ingest.
            src_key = obj["Key"]
            dst_key = dest_prefix.rstrip("/") + "/" + src_key
            s3.copy_object(
                Bucket=bronze_bucket,
                Key=dst_key,
                CopySource={"Bucket": bronze_bucket, "Key": src_key},
                MetadataDirective="COPY",
            )
            copied += 1

    log("replay_done", scanned=scanned, copied=copied)
    return {
        "scanned": scanned,
        "copied": copied,
        "dest_prefix": dest_prefix,
        "start": _iso_z(start),
        "end": _iso_z(end),
    }
