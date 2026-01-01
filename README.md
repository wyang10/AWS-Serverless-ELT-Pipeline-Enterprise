# AWS Serverless ELT Pipeline — S3 → Lambda → SQS → Lambda → S3 (Production-lite)

## An intentionally lite version of end to end serverless pipeline:

- **Bronze (raw)**: `S3` JSON/JSONL
- **Ingest**: `Lambda` (object-level idempotency via DynamoDB) → `SQS`
- **Transform**: `Lambda` (batch from SQS; partial batch failure) → **Silver** `S3` (**Parquet**)

### Scope 
- No dependency on VPC/EC2.
- API Gateway not used in the minimal build.

## Intro

- Built a production-lite serverless ELT pipeline on AWS: S3 (bronze JSON/JSONL) → Lambda (idempotent ingest) → SQS → Lambda (batch transform) → S3 (silver Parquet).
- Implemented S3 object-level idempotency using DynamoDB conditional writes + TTL to prevent duplicate ingestion on retries/events.
- Designed resilient SQS processing with Lambda partial batch failure reporting and DLQ redrive for poisoned messages.
- Delivered infra-as-code with Terraform modules and reproducible build/deploy workflow.

## Architecture

```
S3 (bronze/*.jsonl)
  └─(ObjectCreated)
     Lambda ingest (idempotent via DynamoDB)
        └─ SQS (events) ──(event source mapping)──> Lambda transform (Parquet)
              └─ DLQ (optional)
                                └─ S3 (silver/*.parquet)
```

## Repo layout

```
repo-root/
├─ README.md
├─ Makefile
├─ scripts/
│  ├─ replay_from_s3.py
│  └─ gen_fake_events.py
├─ lambdas/
│  ├─ ingest/
│  │  ├─ app.py
│  │  ├─ requirements.txt
│  │  └─ tests/
│  ├─ transform/
│  │  ├─ app.py
│  │  ├─ requirements.txt
│  │  └─ tests/
│  └─ shared/
│     ├─ __init__.py
│     ├─ schemas.py
│     └─ utils.py
└─ infra/
   └─ terraform/
      ├─ backend/backend.hcl
      ├─ modules/
      └─ envs/
         └─ dev/
```

## Prereqs

- Python 3.11+
- Terraform 1.6+
- AWS credentials for a **dev** account (or a sandbox account)
- Optional: Docker (only if you prefer containerized builds)

## Quickstart (dev)

1) Build Lambda zips:

- `python -m pip install -r requirements-dev.txt`
- `make build`

2) Deploy infra:

- `make tf-init`
- `TF_AUTO_APPROVE=1 make tf-apply`

3) Upload raw events into Bronze:

- `python scripts/gen_fake_events.py --type shipments --count 50 --format jsonl --out /tmp/shipments.jsonl`
- `python scripts/gen_fake_events.py --type shipments --count 50 --format json --out /tmp/shipments.json`
- `aws s3 cp /tmp/shipments.jsonl s3://<bronze_bucket>/bronze/shipments/dt=2025-01-01/shipments.jsonl`

4) Verify outputs:

- Check CloudWatch logs for both Lambdas
- Look for Parquet objects under `s3://<silver_bucket>/silver/<type>/dt=YYYY-MM-DD/`

## Replay / backfill

Two options depending on your IAM permissions:

- **Replay via S3 copy (recommended)**: copies objects to a new key under `bronze/` so the normal S3 → ingest → SQS path runs (does not require your user to have `sqs:SendMessage`).
  - `python scripts/replay_via_s3_copy.py --bucket <bronze_bucket> --prefix bronze/shipments/ --dest-prefix bronze/replay/2026-01-01T00-00-00Z --start 2026-01-01T00:00:00Z --end 2026-01-02T00:00:00Z`
- **Replay directly to SQS**: reads Bronze objects and publishes events straight into SQS (requires `sqs:SendMessage` on the queue).
  - `python scripts/replay_from_s3.py --bucket <bronze_bucket> --prefix bronze/shipments/ --queue-url <queue_url> --start 2026-01-01T00:00:00Z --end 2026-01-02T00:00:00Z`

## Notes

- **Idempotency scope**: ingest is idempotent at *S3 object* granularity (`bucket/key#etag`).
- **Visibility**: both Lambdas log structured JSON lines; transform uses SQS partial batch response.
- **Cost**: this uses only S3/SQS/Lambda/DynamoDB/CloudWatch.

### IAM gotchas

Some orgs allow creating IAM roles but **disallow tagging IAM/SQS** (missing `iam:TagRole` / `sqs:TagQueue`), which can show up as `AccessDenied` on `CreateRole`/`CreateQueue` when tags are included.
This repo disables tags for IAM roles and SQS queues by default in `infra/terraform/envs/dev/main.tf:1`.

If you still hit IAM/SQS permissions:

- **IAM role name restrictions**: set `iam_name_prefix` in `infra/terraform/envs/dev/dev.tfvars:1` to a permitted prefix.
- **SQS tag read restrictions** (e.g., missing `sqs:ListQueueTags`): pre-create the queue and feed Terraform:
  - `python scripts/create_sqs_queue.py --name <project>-<suffix>-events --with-dlq --region us-east-2 --out infra/terraform/envs/dev/queue.auto.tfvars.json`
  - Terraform will auto-load `*.auto.tfvars.json` and skip managing SQS when `existing_queue_url`/`existing_queue_arn` are provided.
- **Attach a DLQ to an existing queue**:
  - `python scripts/ensure_dlq_for_queue.py --queue-url <queue_url> --dlq-name <queue_name>-dlq --region us-east-2`
  - Then add `existing_dlq_url` / `existing_dlq_arn` into `infra/terraform/envs/dev/queue.auto.tfvars.json` (optional; used for outputs/observability).

### Transform dependency

The transform function writes Parquet via the AWS SDK for pandas layer (includes `pyarrow`) configured in `infra/terraform/envs/dev/dev.tfvars:1`.

### Observability (alarms/dashboard)

Terraform can create CloudWatch alarms + a dashboard via `infra/terraform/modules/observability/main.tf:1`, but many restricted dev accounts block:

- `cloudwatch:PutMetricAlarm`
- `cloudwatch:PutDashboard`

In that case, keep `observability_enabled = false` (default in `infra/terraform/envs/dev/dev.tfvars:1`).
