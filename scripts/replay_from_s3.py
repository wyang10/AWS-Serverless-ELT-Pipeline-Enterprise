#!/usr/bin/env python3
import argparse
import json
from datetime import datetime, timezone

import boto3


def _parse_dt(s: str) -> datetime:
    # ISO-8601, e.g. 2025-01-01T00:00:00Z
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay S3 JSON/JSONL objects into SQS.")
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--queue-url", required=True)
    parser.add_argument("--start", required=True, help="ISO time, e.g. 2025-01-01T00:00:00Z")
    parser.add_argument("--end", required=True, help="ISO time, e.g. 2025-01-02T00:00:00Z")
    args = parser.parse_args()

    s3 = boto3.client("s3")
    sqs = boto3.client("sqs")
    start = _parse_dt(args.start)
    end = _parse_dt(args.end)

    paginator = s3.get_paginator("list_objects_v2")
    total = 0
    for page in paginator.paginate(Bucket=args.bucket, Prefix=args.prefix):
        for obj in page.get("Contents", []):
            last_modified = obj["LastModified"].astimezone(timezone.utc)
            if not (start <= last_modified <= end):
                continue

            body = s3.get_object(Bucket=args.bucket, Key=obj["Key"])["Body"].read().decode("utf-8")
            lines = [ln for ln in body.splitlines() if ln.strip()]
            entries = []
            for i, line in enumerate(lines):
                payload = json.loads(line)
                entries.append({"Id": str(i), "MessageBody": json.dumps(payload)})
                if len(entries) == 10:
                    sqs.send_message_batch(QueueUrl=args.queue_url, Entries=entries)
                    total += len(entries)
                    entries = []
            if entries:
                sqs.send_message_batch(QueueUrl=args.queue_url, Entries=entries)
                total += len(entries)

    print(f"replayed_messages={total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

