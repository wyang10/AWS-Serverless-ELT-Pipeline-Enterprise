#!/usr/bin/env python3
import argparse
import json
from typing import Optional

import boto3
from botocore.exceptions import ClientError


def _queue_arn(sqs, queue_url: str) -> str:
    attrs = sqs.get_queue_attributes(QueueUrl=queue_url, AttributeNames=["QueueArn"])["Attributes"]
    return attrs["QueueArn"]

def _find_queue_url_by_name(sqs, queue_name: str) -> Optional[str]:
    urls = sqs.list_queues(QueueNamePrefix=queue_name).get("QueueUrls", [])
    for url in urls:
        if url.endswith("/" + queue_name):
            return url
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Attach a DLQ to an existing SQS queue (no tag APIs).")
    parser.add_argument("--queue-url", required=True)
    parser.add_argument("--region", default=None)
    parser.add_argument("--dlq-name", required=True)
    parser.add_argument("--max-receive-count", type=int, default=5)
    parser.add_argument("--visibility-timeout-seconds", type=int, default=180)
    parser.add_argument("--message-retention-seconds", type=int, default=345600)  # 4 days
    parser.add_argument("--out", default="-", help="Write JSON with dlq_url/dlq_arn to this path (default: stdout)")
    args = parser.parse_args()

    session = boto3.session.Session(region_name=args.region)
    sqs = session.client("sqs")

    dlq_url: Optional[str] = None
    try:
        dlq_url = sqs.create_queue(
            QueueName=args.dlq_name,
            Attributes={
                "VisibilityTimeout": str(args.visibility_timeout_seconds),
                "MessageRetentionPeriod": str(args.message_retention_seconds),
            },
        )["QueueUrl"]
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") != "QueueAlreadyExists":
            raise
        dlq_url = _find_queue_url_by_name(sqs, args.dlq_name)
        if not dlq_url:
            raise RuntimeError(f"DLQ exists but URL not discoverable: {args.dlq_name}") from e

    dlq_arn = _queue_arn(sqs, dlq_url)

    sqs.set_queue_attributes(
        QueueUrl=args.queue_url,
        Attributes={
            "RedrivePolicy": json.dumps(
                {"deadLetterTargetArn": dlq_arn, "maxReceiveCount": args.max_receive_count},
                separators=(",", ":"),
            )
        },
    )

    payload = {"dlq_url": dlq_url, "dlq_arn": dlq_arn}
    if args.out == "-":
        print(json.dumps(payload, indent=2))
    else:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(json.dumps(payload, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
