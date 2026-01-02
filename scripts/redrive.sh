#!/usr/bin/env bash
set -euo pipefail

# Redrive messages from a DLQ back to the main queue (SQS native redrive).
#
# Usage:
#   scripts/redrive.sh [DLQ_URL] [QUEUE_URL]
#
# If URLs are not provided, it will use Terraform outputs (dev env).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DLQ_URL="${1:-}"
QUEUE_URL="${2:-}"

if [[ -z "$DLQ_URL" ]]; then
  DLQ_URL="$(terraform -chdir=infra/terraform/envs/dev output -raw dlq_url)"
fi

if [[ -z "$QUEUE_URL" ]]; then
  QUEUE_URL="$(terraform -chdir=infra/terraform/envs/dev output -raw queue_url)"
fi

DLQ_ARN="$(aws sqs get-queue-attributes --queue-url "$DLQ_URL" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)"
QUEUE_ARN="$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text)"

echo "DLQ_ARN=$DLQ_ARN"
echo "QUEUE_ARN=$QUEUE_ARN"

aws sqs start-message-move-task --source-arn "$DLQ_ARN" --destination-arn "$QUEUE_ARN" >/dev/null
echo "Started message move task."
echo "Check status:"
echo "  aws sqs list-message-move-tasks --source-arn \"$DLQ_ARN\""

