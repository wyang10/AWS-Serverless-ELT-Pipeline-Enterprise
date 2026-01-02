import json
import os
from datetime import datetime
from typing import Any, Dict, List

import boto3
import yaml

s3 = boto3.client("s3")

DATASET = "ups_shipping"


def _load_config() -> Dict[str, Any]:
    # Default config path inside repo packaging; adjust if you package differently.
    # In Lambda, you'll likely ship configs/ into the deployment zip.
    config_path = os.environ.get("CONFIG_PATH", f"configs/{DATASET}.yaml")
    with open(config_path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def _parse_dt(event_ts: str) -> str:
    # Expect ISO8601; fall back to today.
    try:
        dt = datetime.fromisoformat(event_ts.replace("Z", "+00:00")).date()
        return dt.isoformat()
    except Exception:
        return datetime.utcnow().date().isoformat()


def transform_record(raw: Dict[str, Any], cfg: Dict[str, Any]) -> Dict[str, Any]:
    """
    TODO: customize mapping here. Keep output aligned with cfg["output_columns"].
    """
    # Example mapping (replace with your real fields)
    event_id = raw.get("event_id") or raw.get("id") or ""
    event_ts = raw.get("event_ts") or raw.get("timestamp") or ""
    dt = raw.get("dt") or _parse_dt(event_ts or "")

    out = {
        "event_id": str(event_id),
        "dt": dt,
        "carrier": raw.get("carrier", "UPS"),
        "tracking_number": raw.get("tracking_number") or raw.get("tracking") or "",
        "status": raw.get("status") or raw.get("event_type") or "",
        "event_ts": event_ts,
        "raw_source": "s3_bronze",
    }
    return out


def lambda_handler(event, context):
    """
    Expected input (from SQS/Lambda mapping) could be:
      - S3 event record
      - SQS event with body containing S3 info
    Keep this handler minimal; your existing pipeline likely already standardizes the message.
    """
    cfg = _load_config()

    # This handler assumes event contains an array of records with bucket/key
    # Example shape:
    # { "records": [ {"bucket":"...", "key":"..."}, ... ] }
    records = event.get("records") or event.get("Records") or []

    out_rows: List[Dict[str, Any]] = []

    for r in records:
        bucket = (r.get("bucket") or {}).get("name") or r.get("bucket")
        key = (r.get("object") or {}).get("key") or r.get("key")
        if not bucket or not key:
            # skip unknown shapes; keep handler resilient
            continue

        obj = s3.get_object(Bucket=bucket, Key=key)
        body = obj["Body"].read().decode("utf-8")

        # Supports JSONL
        for line in body.splitlines():
            if not line.strip():
                continue
            raw = json.loads(line)
            out_rows.append(transform_record(raw, cfg))

    return {
        "dataset": cfg["dataset"],
        "records_in": len(out_rows),
        "example_out": out_rows[0] if out_rows else None,
    }
