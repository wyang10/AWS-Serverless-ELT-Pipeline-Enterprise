#!/usr/bin/env python3
import argparse
import time
from datetime import datetime, timedelta, timezone

import boto3


def main() -> int:
    parser = argparse.ArgumentParser(description="Check if S3 has recently modified objects under a prefix.")
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--region", default=None)
    parser.add_argument("--suffix", default=".parquet", help="Only consider keys ending with this suffix.")
    parser.add_argument("--window-minutes", type=int, default=30)
    parser.add_argument("--sleep-seconds", type=int, default=15)
    parser.add_argument("--max-attempts", type=int, default=20)
    args = parser.parse_args()

    region = args.region
    s3 = boto3.client("s3", region_name=region)
    since = datetime.now(timezone.utc) - timedelta(minutes=args.window_minutes)

    for _ in range(args.max_attempts):
        resp = s3.list_objects_v2(Bucket=args.bucket, Prefix=args.prefix)
        objs = resp.get("Contents", [])
        recent = [
            o
            for o in objs
            if o["Key"].endswith(args.suffix) and o["LastModified"].astimezone(timezone.utc) >= since
        ]
        if recent:
            newest = max(o["LastModified"] for o in recent).astimezone(timezone.utc).isoformat().replace("+00:00", "Z")
            print(
                f"OK: found {len(recent)} recent objects under s3://{args.bucket}/{args.prefix} "
                f"(suffix={args.suffix}, newest={newest})"
            )
            return 0
        time.sleep(args.sleep_seconds)

    print(
        f"FAIL: no recent objects under s3://{args.bucket}/{args.prefix} "
        f"within last {args.window_minutes} minutes (suffix={args.suffix})"
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
