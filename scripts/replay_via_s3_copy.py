#!/usr/bin/env python3
import argparse
from datetime import datetime, timezone

import boto3


def _parse_dt(s: str) -> datetime:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    dt = datetime.fromisoformat(s)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def main() -> int:
    parser = argparse.ArgumentParser(description="Replay S3 objects by copying them to a new key (triggers S3 event).")
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--prefix", required=True, help="Source prefix to scan (e.g., bronze/shipments/)")
    parser.add_argument("--dest-prefix", required=True, help="Destination prefix under the same bucket (must start with bronze/)")
    parser.add_argument("--start", required=True, help="ISO time, e.g. 2025-01-01T00:00:00Z")
    parser.add_argument("--end", required=True, help="ISO time, e.g. 2025-01-02T00:00:00Z")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    s3 = boto3.client("s3")
    start = _parse_dt(args.start)
    end = _parse_dt(args.end)

    copied = 0
    paginator = s3.get_paginator("list_objects_v2")
    for page in paginator.paginate(Bucket=args.bucket, Prefix=args.prefix):
        for obj in page.get("Contents", []):
            last_modified = obj["LastModified"].astimezone(timezone.utc)
            if not (start <= last_modified <= end):
                continue

            src_key = obj["Key"]
            dst_key = args.dest_prefix.rstrip("/") + "/" + src_key
            if args.dry_run:
                print(f"copy s3://{args.bucket}/{src_key} -> s3://{args.bucket}/{dst_key}")
                copied += 1
                continue

            s3.copy_object(
                Bucket=args.bucket,
                Key=dst_key,
                CopySource={"Bucket": args.bucket, "Key": src_key},
                MetadataDirective="COPY",
            )
            copied += 1

    print(f"copied_objects={copied}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

