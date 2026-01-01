"""
Step Functions task: lightweight “quality probe” for Silver outputs.

This is intentionally simple/cheap:
- It checks whether at least N Parquet objects exist under `silver/<record_type>/`
  with `LastModified >= since`.

Inputs (from Step Functions execution input):
- `silver_bucket` (required)
- `silver_prefix` (optional, default "silver")
- `record_type` (optional, default "shipments")
- `since` (required) OR `execution_start_time` (set by the workflow)
- `min_parquet_objects` (optional, default 1)
"""

from datetime import datetime, timezone
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


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    s3 = boto3.client("s3")

    payload = event.get("input") if isinstance(event.get("input"), dict) else event

    silver_bucket = payload["silver_bucket"]
    silver_prefix = payload.get("silver_prefix", "silver").strip("/")
    record_type = payload.get("record_type", "shipments")
    since_s = payload.get("since") or event.get("since") or event.get("execution_start_time")
    if not since_s:
        raise ValueError("Missing since (or execution_start_time)")
    since = _parse_dt(since_s)
    min_parquet_objects = int(payload.get("min_parquet_objects", 1))

    prefix = f"{silver_prefix}/{record_type}/"
    found = 0
    newest = None

    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=silver_bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".parquet"):
                continue
            last_modified = obj["LastModified"].astimezone(timezone.utc)
            if last_modified >= since:
                found += 1
                newest = max(newest, last_modified) if newest else last_modified

    ok = found >= min_parquet_objects
    log(
        "quality_check",
        ok=ok,
        found=found,
        min_required=min_parquet_objects,
        silver_bucket=silver_bucket,
        prefix=prefix,
        since=since.isoformat().replace("+00:00", "Z"),
        newest=(newest.isoformat().replace("+00:00", "Z") if newest else None),
    )

    return {"ok": ok, "found": found, "min_required": min_parquet_objects, "prefix": prefix}
