# AWS Serverless ELT Pipeline (v2.0 — Enterprise Track)

Production-lite, resume-ready serverless ELT: **S3 (bronze JSONL) → Lambda ingest → SQS (+ DLQ) → Lambda transform → S3 (silver Parquet)**, with optional orchestration, catalog/query, quality gating, and observability.

## Architecture

```text
S3 (bronze/*.jsonl)
  └─ ObjectCreated
     └─ Lambda ingest (Powertools logs/metrics/idempotency)
         └─ SQS (events) + DLQ (optional)
             └─ Lambda transform (Parquet writer)
                 └─ S3 (silver/…/*.parquet)
                     └─ (optional) Glue Catalog/Crawler → Athena
                     └─ (optional) Step Functions → Glue Job (+ Great Expectations gate)
```

No VPC/EC2 is required for the minimal path.

## What’s included

- **Idempotency:** AWS Lambda Powertools Idempotency backed by DynamoDB (conditional writes + TTL under the hood).
- **Replay/Recovery:** `scripts/replay.sh` (S3-copy replay) + `scripts/redrive.sh` (SQS native redrive).
- **Ops orchestration (optional):** Step Functions workflow for replay/backfill + downstream readiness polling.
- **Catalog/Query (optional):** Glue Data Catalog + Crawler to query `silver/` Parquet in Athena.
- **Quality gate (optional):** Glue Job + Step Functions (optionally auto-triggered via EventBridge).
- **Observability (optional):** CloudWatch Dashboard + Alarms.
- **Delivery:** Terraform modules + GitHub Actions (CI + manual Terraform plan/apply).

## v1 vs v2.0

| Aspect | v1 (Minimal) | v2.0 (Enterprise track) |
|---|---|---|
| Pipeline | S3 → Lambda → SQS → Lambda → S3 | EventBridge / Step Functions + Glue + GE |
| Idempotency | DDB object-level lock| Powertools (DynamoDB TTL) + replay / backfill |
| Recovery | Manual | Replay + DLQ redrive `scripts/.sh` helpers |
| Queryability | S3 only | Glue Catalog / Crawler + Athena |
| Data quality | — | Glue Job + Great Expectations gate |
| Storage | JSONL → Parquet | Parquet + Glue tables (compaction) + Athena |
| Observability | Logs only | CloudWatch Dashboards + Alarms |
| CI/CD | Local apply | CI + manual Terraform plan/apply (keys/OIDC) |

## Quickstart (local)

```bash
git clone https://github.com/wyang10/AWS-Serverless-ELT-Pipeline-Enterprise.git
cd AWS-Serverless-ELT-Pipeline-Enterprise

python3 -m venv .venv && source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements-dev.txt

export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2
aws sts get-caller-identity

make build
make tf-init
TF_AUTO_APPROVE=1 make tf-apply
```

Run end-to-end verification (screenshot-able checks):

```bash
make verify-e2e
```

For the full E2E checklist and troubleshooting, see `Instructions.md`.

## Feature toggles (Terraform)

Edit `infra/terraform/envs/dev/dev.tfvars`:

- `observability_enabled`: CloudWatch dashboard + alarms
- `ops_enabled`: ops Step Functions workflow (replay + polling)
- `glue_enabled`: Glue database + crawler (Athena tables)
- `glue_job_enabled`: compaction/recompute Glue job
- `ge_enabled`: Great Expectations Glue job + state machine (quality gate)
- `ge_workflow_enabled`: Step Functions quality gate workflow
- `ge_emit_events_from_transform`: have `transform` emit EventBridge events after success
- `ge_eventbridge_enabled`: create an EventBridge rule to auto-start the GE workflow

Recommendation: keep `ge_emit_events_from_transform=false` and `ge_eventbridge_enabled=false` until you’re ready to run the gate automatically (and handle failures/quarantine paths).

## Common ops commands

- Deploy: `make build && TF_AUTO_APPROVE=1 make tf-apply`
- Destroy: `TF_AUTO_APPROVE=1 make tf-destroy` (empty S3 buckets first; details in `Instructions.md`)
- Start ops workflow: `make ops-start` (then `make ops-status`)
- Run Glue crawler: `make glue-crawler-start`
- Run compaction job: `make glue-job-start GLUE_RECORD_TYPE=shipments GLUE_DT=2025-12-31 GLUE_OUTPUT_PREFIX=silver_compacted`
- Run GE gate: `make ge-start GE_RECORD_TYPE=shipments GE_DT=2025-12-31`

## Repo layout (actual)

```text
.
├─ .github/workflows/                 # CI + manual terraform workflow
├─ infra/terraform/
│  ├─ backend/backend.hcl
│  ├─ envs/dev/                       # entrypoint env (dev.tfvars, outputs.tf)
│  └─ modules/                        # reusable IaC modules
├─ lambdas/
│  ├─ ingest/app.py                   # S3 event → SQS (idempotent)
│  ├─ transform/app.py                # SQS batch → Parquet in S3
│  ├─ workflows/                      # Step Functions task Lambdas
│  └─ shared/                         # shared helpers/schema
├─ scripts/                           # replay/redrive/scaffold/verification helpers
├─ templates/                         # dataset scaffolding templates
├─ configs/                           # dataset configs (scaffolded)
├─ dq/                                # lightweight DQ rules (scaffolded)
├─ data_samples/                      # sample JSONL (scaffolded)
├─ demo/                              # screenshots
├─ Instructions.md
└─ LICENSE
```

## Screenshots

![](demo/1.png)
![](demo/2.png)
![](demo/3.png)

## License

MIT — see `LICENSE`.
