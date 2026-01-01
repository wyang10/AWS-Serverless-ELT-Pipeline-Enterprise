# AWS Serverless ELT Pipeline (Enterprise track) — v2.0

This repo is the **v2.0 / enterprise-ish track**. It starts from the v1 minimal serverless ELT and adds orchestration, catalog, and data quality.

- v1 (minimal): S3 → Lambda → SQS → Lambda → S3 Parquet
- v2.0 (this repo): v1 + Step Functions ops workflow + Glue Catalog/Crawler + Glue Jobs + Great Expectations quality gate

Planned rollout: `ROADMAP.md`.

---

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

## v1 vs v2.0 highlights

- **v1** focuses on the core pipeline and idempotent ingestion.
- **v2.0** adds “enterprise-ish” operability:
  - Step Functions **ops workflow** for replay/backfill + quality polling (`make ops-start`)
  - Glue **Data Catalog + Crawler** so Athena can query Silver as tables
  - Glue **compaction/recompute job** (safe outputs to a separate prefix)
  - Great Expectations **quality gate** implemented as a Glue job orchestrated by Step Functions

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

## Ops workflow (EventBridge + Step Functions)

The v2 track adds a minimal “ops” workflow that can be run manually or on a schedule:

- **Replay/backfill** by copying S3 objects to a new key under `bronze/` (triggers the normal ingest path)
- **Inspect** by checking Silver contains recent Parquet outputs (poll + retry)

Terraform wiring lives in:

- `infra/terraform/modules/workflow_ops/main.tf`
- `infra/terraform/envs/dev/main.tf`

To enable in dev:

- Build artifacts (adds `build/ops_replay.zip` + `build/ops_quality.zip`): `make build`
- Set in `infra/terraform/envs/dev/dev.tfvars`:
  - `ops_enabled = true`
  - `ops_workflow_id = "ops-replay-and-quality-gate"`
  - Optional schedule: `ops_schedule_enabled = true` and `ops_schedule_expression = "rate(1 day)"`
- Deploy: `make tf-init` then `TF_AUTO_APPROVE=1 make tf-apply`

To start it manually:

- One-liners:
  - Start: `make ops-start`
  - Status: `make ops-status`
  - History: `make ops-history`
- Or raw CLI (if you prefer):
  - `aws stepfunctions start-execution --region us-east-2 --state-machine-arn $(terraform -chdir=infra/terraform/envs/dev output -raw ops_state_machine_arn) --input '{
    "bronze_bucket":"<bronze_bucket>",
    "src_prefix":"bronze/shipments/",
    "dest_prefix_base":"bronze/replay/manual",
    "window_hours":24,
    "silver_bucket":"<silver_bucket>",
    "silver_prefix":"silver",
    "record_type":"shipments",
    "min_parquet_objects":1,
    "poll_interval_seconds":30,
    "max_attempts":20
  }'`

## Notes

- **Idempotency scope**: ingest is idempotent at *S3 object* granularity (`bucket/key#etag`).
- **Visibility**: both Lambdas log structured JSON lines; transform uses SQS partial batch response.
- **Cost**: this uses only S3/SQS/Lambda/DynamoDB/CloudWatch.

## Glue Data Catalog (Catalog + Crawler)

Enable the crawler so Athena (or a future warehouse) can query Silver Parquet as tables.

- Set in `infra/terraform/envs/dev/dev.tfvars`:
  - `glue_enabled = true`
  - Optional: `glue_silver_prefix = "silver/"` (default) and `glue_table_prefix = "silver_"`
- Deploy: `TF_AUTO_APPROVE=1 make tf-apply`
- Run the crawler:
  - Start: `make glue-crawler-start`
  - Status: `make glue-crawler-status`

After the crawler finishes, you should see a Glue database + tables; then you can query via Athena.

## Glue Job (Compaction / Recompute)

Optional next step: move “recompute / small-file compaction / per-day rerun” to a Glue job.

- Enable the job in `infra/terraform/envs/dev/dev.tfvars`:
  - `glue_job_enabled = true`
  - Optional: `glue_job_name = "<name>"` and `glue_job_script_key = "glue/scripts/compact_silver.py"`
- Deploy: `TF_AUTO_APPROVE=1 make tf-apply`
- Run a compaction for a single partition:
  - Start: `make glue-job-start GLUE_RECORD_TYPE=shipments GLUE_DT=2025-12-31 GLUE_OUTPUT_PREFIX=silver_compacted`
  - Status: `make glue-job-status`

## Great Expectations (Quality Gate)

Run Great Expectations inside a Glue job, orchestrated by Step Functions as a “quality gate”.

- Enable in `infra/terraform/envs/dev/dev.tfvars`:
  - `ge_enabled = true` (creates the Glue GE job)
  - `ge_workflow_enabled = true` (creates the Step Functions gate)
  - Optional auto-trigger from transform:
    - `ge_emit_events_from_transform = true`
    - `ge_eventbridge_enabled = true`
  - Optional failure handling:
    - `ge_notification_topic_arn = "<sns_topic_arn>"` (or reuse `alarm_notification_topic_arn`)
    - `ge_quarantine_enabled = true` (writes a marker JSON to `ge_quarantine_prefix`)
- Deploy: `TF_AUTO_APPROVE=1 make tf-apply`
- Manual run:
  - `make ge-start GE_RECORD_TYPE=shipments GE_DT=2025-12-31 GE_RESULT_PREFIX=ge/results`
  - `make ge-status`
  - `make ge-history`

### Auto-trigger (optional)

Two toggles control whether the GE gate runs automatically after `transform` writes a partition:

- Keep **manual** (recommended for dev / controlled runs):
  - `ge_emit_events_from_transform = false`
  - `ge_eventbridge_enabled = false`
- Enable **auto-trigger** (recommended for “prod-like” behavior):
  - `ge_emit_events_from_transform = true` (transform emits an EventBridge event per written partition)
  - `ge_eventbridge_enabled = true` (EventBridge rule starts the GE state machine)

When auto-trigger is on, every successful transform write may trigger a validation run; keep it off if you are iterating quickly or don’t want extra runs/cost.

## Athena quick queries

Get the Glue database name from Terraform:

- `terraform -chdir=infra/terraform/envs/dev output -raw glue_database_name`

Then run queries (replace `<db>` with that value):

```sql
-- 1) Latest shipments
SELECT dt, shipment_id, origin, destination, carrier, weight_kg, event_time
FROM "<db>".silver
WHERE record_type = 'shipments'
ORDER BY dt DESC, event_time DESC
LIMIT 20;

-- 2) Row counts per partition/day
SELECT dt, COUNT(*) AS rows
FROM "<db>".silver
WHERE record_type = 'shipments'
GROUP BY dt
ORDER BY dt DESC;

-- 3) Simple sanity checks (range / uniqueness signal)
SELECT
  dt,
  MIN(weight_kg) AS min_weight_kg,
  MAX(weight_kg) AS max_weight_kg,
  APPROX_DISTINCT(shipment_id) AS approx_unique_shipments
FROM "<db>".silver
WHERE record_type = 'shipments'
GROUP BY dt
ORDER BY dt DESC;
```

## Cleanup (cost control)

Terraform destroy will remove most resources, but **S3 buckets must be empty** first.

- Destroy:
  - `TF_AUTO_APPROVE=1 make tf-destroy`
- If destroy fails because buckets are not empty:
  - `BRONZE=$(terraform -chdir=infra/terraform/envs/dev output -raw bronze_bucket)`
  - `SILVER=$(terraform -chdir=infra/terraform/envs/dev output -raw silver_bucket)`
  - `aws s3 rm "s3://$BRONZE" --recursive --region us-east-2`
  - `aws s3 rm "s3://$SILVER" --recursive --region us-east-2`
  - Re-run: `TF_AUTO_APPROVE=1 make tf-destroy`

Notes:

- If you enabled Glue resources, Terraform will attempt to delete the Glue database/crawler/job; if anything is left behind, remove it in the Glue console.
- If you used an externally-managed SQS queue via `infra/terraform/envs/dev/*.auto.tfvars.json`, Terraform won’t delete that queue; delete it separately if needed.

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
