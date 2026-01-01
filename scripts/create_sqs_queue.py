#!/usr/bin/env python3
import argparse
import json
from typing import Any, Dict, Optional

import boto3


def _queue_arn(sqs, queue_url: str) -> str:
    attrs = sqs.get_queue_attributes(QueueUrl=queue_url, AttributeNames=["QueueArn"])["Attributes"]
    return attrs["QueueArn"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Create an SQS queue (optionally with a DLQ) without tag APIs.")
    parser.add_argument("--name", required=True, help="Main queue name")
    parser.add_argument("--region", default=None, help="AWS region (defaults to AWS_REGION/AWS_DEFAULT_REGION)")
    parser.add_argument("--with-dlq", action="store_true", help="Create a DLQ and attach redrive policy")
    parser.add_argument("--dlq-name", default=None, help="DLQ name (default: <name>-dlq)")
    parser.add_argument("--max-receive-count", type=int, default=5)
    parser.add_argument("--visibility-timeout-seconds", type=int, default=180)
    parser.add_argument("--message-retention-seconds", type=int, default=345600)
    parser.add_argument("--out", default="-", help="Write tfvars JSON to this path (default: stdout)")
    args = parser.parse_args()

    session = boto3.session.Session(region_name=args.region)
    sqs = session.client("sqs")

    dlq_url: Optional[str] = None
    dlq_arn: Optional[str] = None
    if args.with_dlq:
        dlq_name = args.dlq_name or f"{args.name}-dlq"
        dlq_url = sqs.create_queue(
            QueueName=dlq_name,
            Attributes={
                "VisibilityTimeout": str(args.visibility_timeout_seconds),
                "MessageRetentionPeriod": str(args.message_retention_seconds),
            },
        )["QueueUrl"]
        dlq_arn = _queue_arn(sqs, dlq_url)

    attributes: Dict[str, str] = {
        "VisibilityTimeout": str(args.visibility_timeout_seconds),
        "MessageRetentionPeriod": str(args.message_retention_seconds),
    }
    if dlq_arn:
        attributes["RedrivePolicy"] = json.dumps(
            {"deadLetterTargetArn": dlq_arn, "maxReceiveCount": args.max_receive_count},
            separators=(",", ":"),
        )

    queue_url = sqs.create_queue(QueueName=args.name, Attributes=attributes)["QueueUrl"]
    queue_arn = _queue_arn(sqs, queue_url)

    payload: Dict[str, Any] = {
        "existing_queue_url": queue_url,
        "existing_queue_arn": queue_arn,
    }
    if dlq_url:
        payload["existing_dlq_url"] = dlq_url
    if dlq_arn:
        payload["existing_dlq_arn"] = dlq_arn

    out_f = None
    try:
        if args.out == "-":
            print(json.dumps(payload, indent=2))
        else:
            out_f = open(args.out, "w", encoding="utf-8")
            out_f.write(json.dumps(payload, indent=2) + "\n")
    finally:
        if out_f is not None:
            out_f.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
