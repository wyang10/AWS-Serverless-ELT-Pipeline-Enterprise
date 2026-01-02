# Instructions (Local Setup + E2E Screenshot Checklist)

This file is the “how to run it” companion to `README.md`.

## Local setup (fresh clone)

```bash
python3 -m venv .venv && source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements-dev.txt
```

AWS identity/region:

```bash
export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

# If you use an IAM User/assumed-role profile:
export AWS_PROFILE=audrey-tf

aws sts get-caller-identity
```

If `audrey-tf` does not exist locally, create a local alias profile:

```bash
make profile-audrey-tf
export AWS_PROFILE=audrey-tf
aws sts get-caller-identity
```

Deploy:

```bash
make build
make tf-init
TF_AUTO_APPROVE=1 make tf-apply
```

## E2E screenshot checklist (run in order)

You can run everything at once:

```bash
make verify-e2e
```

Or capture screenshots step-by-step using the targets below. For each step: **Command/Console → Pass criteria → Screenshot**.

### 0) Who am I (profile/region)

- Command: `make verify-whoami`
- Pass: shows Account `818466672474` and an Arn containing `user/audrey-tf` (or your intended role/user)
- Screenshot: terminal output block

### 1) Terraform outputs are from the right state

- Command: `make verify-tf-outputs`
- Pass: prints non-empty outputs (buckets, lambdas, queue URLs, optional resources)
- Screenshot: terminal output block

### 2) S3 → ingest notification exists (bronze bucket)

- Command: `make verify-s3-notifications`
- Console: S3 → your `bronze_bucket` → **Properties** → **Event notifications**
- Pass: ObjectCreated notification targets the ingest Lambda (prefix includes `bronze/`)
- Screenshot: Event notification card

### 3) Lambda functions exist and have logs

- Command: `make verify-lambdas`
- Console: Lambda → `ingest_lambda` / `transform_lambda` → **Monitor** → **Logs**
- Pass: verification command succeeds; log groups exist and show recent invocations after seeding
- Screenshot: Lambda Monitor → Logs view

### 4) DynamoDB idempotency table (TTL enabled)

- Command: `make verify-ddb`
- Console: DynamoDB → table `idempotency_table_name` → **Additional settings** → TTL
- Pass: TTL is `ENABLED` and items can be scanned
- Screenshot: TTL enabled card + terminal scan output

### 5) SQS + DLQ health

- Command: `make verify-sqs`
- Console: SQS → main queue + DLQ → **Monitoring**
- Pass: main queue has ~0 messages and low age; DLQ has 0 messages
- Screenshot: Monitoring charts for both queues

### 6) Seed data end-to-end (S3 → Lambdas → Silver)

- Command: `make verify-seed`
- Pass: uploads a JSONL batch to `bronze/…` and triggers the pipeline
- Screenshot: terminal output + S3 object list (optional)

### 7) Silver outputs exist (Parquet)

- Command: `make verify-silver`
- Console: S3 → your `silver_bucket` → `silver/<record_type>/…`
- Pass: Parquet objects exist under `silver/`
- Screenshot: S3 object list + terminal output

### 8) Idempotency behavior (same object event is skipped)

- Command: `make verify-idempotency`
- Pass: second invocation is reported as a no-op/duplicate (implementation-specific message), and DynamoDB does not keep growing for identical inputs
- Screenshot: terminal output (both runs)

### 9) Glue + Athena queryability (optional)

- Command: `make verify-glue`
- Console:
  - Glue → Databases/Tables (table created)
  - Athena → Query editor
- Pass: Glue crawler is `READY` and last crawl is `SUCCEEDED`; Athena can query the `silver` table
- Screenshot: Glue table schema + Athena query results

Athena examples (adjust database/table if needed):

```sql
SELECT record_type, dt, COUNT(*) AS cnt
FROM silver
GROUP BY record_type, dt
ORDER BY dt DESC;

SELECT dt, shipment_id, origin, destination, carrier, weight_kg, event_time
FROM silver
WHERE record_type = 'shipments'
ORDER BY dt DESC, event_time DESC
LIMIT 20;
```

### 10) Quality gate (optional: Step Functions + GE/Glue)

- Command: `make verify-ge`
- Console: Step Functions → State machines → `ge_state_machine` → Executions
- Pass: latest execution is `SUCCEEDED` (or failures are intentional test runs)
- Screenshot: execution detail page showing green tasks

### 11) Observability (optional)

- Command: `make verify-observability`
- Console: CloudWatch → Dashboards / Alarms
- Pass: dashboard exists and alarms are visible
- Screenshot: dashboard + alarms list

Note: if you see `Observability disabled or not deployed.`, it usually means `observability_enabled=false` (or the module is intentionally skipped). Observability requires permission to create CloudWatch alarms/dashboards (for example: `cloudwatch:PutMetricAlarm`, `cloudwatch:PutDashboard`).

## Troubleshooting

### README images do not render on GitHub

If you add images like `![](demo/1.png)` and they do not show up:

- The file path is wrong (GitHub is case-sensitive): ensure the file exists exactly at `demo/1.png`.
- The image is not committed/pushed: run `git status`, then `git add demo/1.png && git commit && git push`.
- The filename contains spaces/parentheses/unicode: use `![](<demo/your file name (1).png>)`.

### Common IAM/org policy blockers

- **CloudWatch write restrictions:** set `observability_enabled=false` and apply again, or request CloudWatch write permissions.
- **SQS tag APIs restricted:** Terraform may require `sqs:ListQueueTags` during refresh/create; add the permission or pre-provision the queue and feed URLs via `*.auto.tfvars.json`.

## GitHub Actions (manual Terraform workflow)

The repo includes:

- `.github/workflows/ci.yml`: `pytest` + `terraform fmt -check`
- `.github/workflows/terraform-manual.yml`: manually run `plan/apply/destroy`

For `terraform-manual.yml` using `auth=keys`, add repository secrets:

- `AWS_ACCESS_KEY_ID`: your IAM access key id (e.g. `AKIA…`)
- `AWS_SECRET_ACCESS_KEY`: the corresponding secret access key
- (optional) `AWS_SESSION_TOKEN`: only if you use temporary credentials

For remote Terraform state (recommended for team usage), set `TF_BACKEND_HCL` secret to the contents of `infra/terraform/backend/backend.hcl`.
