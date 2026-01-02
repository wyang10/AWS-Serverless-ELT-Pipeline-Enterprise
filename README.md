# AWS Serverless ELT Pipeline (v2.0) — production-lite, enterprise features by toggles

> 轻量起步，企业化能力随开随用：**S3 → Lambda → SQS → Lambda → S3 (Parquet)**，可选编排、目录、质量门禁与可观测性。

This repo keeps the **minimal pipeline** as the default backbone, then layers optional “enterprise-ish” modules:

- **Core pipeline**: S3 (bronze JSON/JSONL) → Lambda ingest (object-level idempotency) → SQS (+ DLQ) → Lambda transform → S3 (silver Parquet)
- **Orchestration (optional)**: Step Functions ops workflow for replay/backfill/quality polling (`make ops-start`)
- **Catalog / Query (optional)**: Glue Data Catalog + Crawler so Athena can query `silver/` as tables
- **Quality gate (optional)**: Glue Job + Step Functions (with optional auto-trigger via EventBridge)
- **Observability (optional)**: CloudWatch dashboard + alarms
- **Extensibility**: `make scaffold DATASET=<name>` generates dataset config/handler/DQ/sample skeleton

Roadmap: `ROADMAP.md`.

## 🧩 Architecture

```
S3 (bronze/*.jsonl)
  └─(ObjectCreated)
     Lambda ingest (idempotent via DynamoDB)
        └─ SQS (events) ──(event source mapping)──> Lambda transform (Parquet)
              └─ DLQ (optional)
                                └─ S3 (silver/*.parquet)
```

## 🔁 v1 vs v2.0 (what changed)

| Aspect | v1 (Minimal) | v2.0 (Enterprise-ish) |
|---|---|---|
| Pipeline | S3 → Lambda → SQS → Lambda → S3 | Same + optional orchestration |
| Idempotency | DynamoDB TTL (object-level) | Same + replay/backfill workflows |
| Failure handling | SQS + DLQ | Same + redrive helpers |
| Storage | JSONL → Parquet | Same + optional compaction job |
| Queryability | S3 only | Glue Catalog/Crawler + Athena tables |
| Observability | Logs | Optional CloudWatch dashboard + alarms |
| Data quality | — | Optional quality gate (Glue Job + Step Functions) |
| Delivery | Local apply | GitHub Actions: CI + manual plan/apply (supports keys/OIDC) |

## 💼 Resume / Interview snippets (pick one)

<details>
<summary>1-liner (LinkedIn / top of resume)</summary>

Built a production-lite serverless ELT framework on AWS (**S3 → Lambda → SQS → Lambda → S3 Parquet**) with optional orchestration, catalog, replay, and quality gating.

</details>

<details>
<summary>Resume bullets (3–5 bullets)</summary>

- Shipped a serverless ELT pipeline on AWS: S3 bronze JSONL → Lambda ingest → SQS (+ DLQ) → Lambda transform → S3 silver Parquet.
- Implemented object-level idempotency using DynamoDB conditional writes + TTL to prevent duplicate ingestion on retries/events.
- Added operational tooling: Step Functions replay/backfill workflow, SQS DLQ redrive, and one-command dataset scaffolding (`make scaffold DATASET=...`).
- Enabled “query-ready” silver layer via Glue Data Catalog + Crawler for Athena.
- Delivered infrastructure as code (Terraform modules) and CI automation (pytest + terraform fmt; manual Terraform plan/apply workflow).

</details>

<details>
<summary>Interview story (structured)</summary>

- Problem: Needed a simple but robust pipeline for JSONL → Parquet without VPC/EC2, yet with real-world operability.
- Design: S3 event-driven ingest + SQS decoupling + batch transform to partitioned Parquet; add idempotency at the S3 object level.
- Reliability: Partial batch failure handling + DLQ + redrive; replay/backfill via Step Functions and S3-copy re-triggering.
- Operability: CloudWatch dashboard/alarms and a “quality gate” workflow (Glue job orchestrated by Step Functions).

</details>

## Repo layout

```
repo-root/
├─ README.md
├─ Makefile
├─ configs/                 # dataset configs (scaffolded)
├─ dq/                      # per-dataset lightweight DQ rules (scaffolded)
├─ data_samples/            # per-dataset JSONL samples (scaffolded)
├─ templates/               # scaffolding templates
├─ scripts/
│  ├─ gen_fake_events.py
│  ├─ replay_from_s3.py
│  ├─ replay.sh             # wrapper: S3 copy replay
│  ├─ redrive.sh            # wrapper: DLQ → main queue (SQS native redrive)
│  └─ scaffold.sh           # generate new dataset skeleton
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

## 从零开始（安装/部署指引）

下面是一套“从新 clone → 部署 → 造数 → 验证”的完整命令清单（默认区域 `us-east-2`）。

### 0) Clone 代码

```bash
git clone https://github.com/wyang10/AWS-Serverless-ELT-Pipeline-Enterprise.git
cd AWS-Serverless-ELT-Pipeline-Enterprise

# 可选：切到 v2.0 tag（更适合简历/里程碑展示）
git checkout v2.0
```

### 1) Python 虚拟环境 + 依赖

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements-dev.txt
```

### 2) AWS 凭证/区域确认

```bash
# 可选：如果你用的是 profile
export AWS_PROFILE=<your-profile>

# 建议固定 region（Terraform/AWS CLI 都会用到）
export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

aws sts get-caller-identity
```

如果你希望固定使用 IAM User profile（例如 `audrey-tf`）但本机没有该 profile：

```bash
make profile-audrey-tf
export AWS_PROFILE=audrey-tf
aws sts get-caller-identity
```

### 3) 本地单测（可选但推荐）

```bash
source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements-dev.txt
make test

```

### 4) 构建 Lambda 打包产物（build/*.zip）

```bash
make build
```

### 5) Terraform 初始化 + 部署

```bash
make tf-init
TF_AUTO_APPROVE=1 make tf-apply
```

说明：`infra/terraform/envs/dev/dev.tfvars` 里通过开关控制可选模块（ops/glue/ge/observability）。本 repo 默认 `observability_enabled=true`；如果你的账号缺少 CloudWatch `PutMetricAlarm/PutDashboard` 权限，可先设为 `false` 再 apply。

如果你遇到 `sqs:ListQueueTags` 的 403（有些账号禁止读 tags），用下面“无 tag API”的方式绕过：

```bash
# 1) 先在 AWS 里创建队列 + DLQ，并把 URL/ARN 写到 auto tfvars（Terraform 会自动读取）
python3 scripts/create_sqs_queue.py \
  --name serverless-elt-<suffix>-events \
  --with-dlq \
  --region us-east-2 \
  --out infra/terraform/envs/dev/queue.auto.tfvars.json

# 2) 如果之前 Terraform 已经把 queue 资源写入 state，需要移除对应条目（避免 refresh 再触发 ListQueueTags）
terraform -chdir=infra/terraform/envs/dev state list | rg '^module\\.queue' || true
terraform -chdir=infra/terraform/envs/dev state rm 'module.queue[0].aws_sqs_queue.dlq[0]' || true

# 3) 再次 apply
TF_AUTO_APPROVE=1 make tf-apply
```

### 6) 造数并上传到 Bronze（触发整条管道）

```bash
BRONZE=$(terraform -chdir=infra/terraform/envs/dev output -raw bronze_bucket)

python3 scripts/gen_fake_events.py --type shipments --count 50 --format jsonl --out /tmp/shipments.jsonl
aws s3 cp /tmp/shipments.jsonl \
  "s3://$BRONZE/bronze/shipments/manual/shipments-$(date -u +%Y%m%dT%H%M%SZ).jsonl" \
  --region us-east-2
```

### 7) 验证 Silver 产出 Parquet

```bash
SILVER=$(terraform -chdir=infra/terraform/envs/dev output -raw silver_bucket)
aws s3 ls "s3://$SILVER/silver/shipments/" --recursive --region us-east-2 | tail
```

### 8) v2 “企业化”能力（按需）

```bash
# Ops Step Functions（回灌/巡检编排）
make ops-start
make ops-status
make ops-history

# Glue Crawler（让 Athena 有表）
make glue-crawler-start
make glue-crawler-status

# Glue Compaction Job（小文件压缩/按天重跑，输出到安全前缀）
make glue-job-start GLUE_RECORD_TYPE=shipments GLUE_DT=2025-12-31 GLUE_OUTPUT_PREFIX=silver_compacted
make glue-job-status

# GE Quality Gate（Glue Job + Step Functions 闸门）
make ge-start GE_RECORD_TYPE=shipments GE_DT=2025-12-31 GE_RESULT_PREFIX=ge/results
make ge-status
make ge-history
```

## GitHub Actions（更像企业交付）

本仓库包含：

- `.github/workflows/ci.yml`：`pytest` + `terraform fmt -check`
- `.github/workflows/terraform-manual.yml`：手动触发的 `plan/apply/destroy`（企业版工作流）

### terraform-manual：先配 Secrets 再运行

路径：GitHub Repo → Settings → Secrets and variables → Actions → New repository secret

`terraform-manual` 需要在 Repo Secrets 配置 AWS 凭证：

- 触发时选择 `auth=keys`：需要 `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`（可选 `AWS_SESSION_TOKEN`）
- 触发时选择 `auth=oidc`：需要 `AWS_ROLE_TO_ASSUME`（OIDC AssumeRole）
- `TF_BACKEND_HCL`：远端 backend 配置（不提供时只允许 `plan`；会阻止 `apply/destroy` 以避免 runner 本地 state）

## Dataset Scaffold（快速扩展新数据集）

一行生成 4 个文件（config/handler/dq/sample）：

```bash
make scaffold DATASET=ups_shipping
ls -la configs/ups_shipping.yaml lambdas/transform/ups_shipping/handler.py dq/ups_shipping/rules.yaml data_samples/ups_shipping/sample.jsonl
```

下一步：

- 编辑 `configs/<dataset>.yaml`（prefix/idempotency_key/output_columns）
- 实现 `lambdas/transform/<dataset>/handler.py` 的字段映射
- （可选）在 `dq/<dataset>/rules.yaml` 补充轻量规则或映射到 GE

## E2E 验收清单（见截图）

目标：按顺序过一遍就能留存证据。每一步都有「要点 → 命令/控制台路径 → 通过标准（截图点）」。

建议先跑一键版（会依次执行多步 CLI 验证 + 造数 + 等待 Silver）：

- `make verify-e2e`

![](<demo/0-1.png>)
![](<demo/0-2.png>)

如果你希望固定用 IAM User profile（例如 `audrey-tf`），但本机没有该 profile：

- `make profile-audrey-tf`
- 然后：`export AWS_PROFILE=audrey-tf`

### 0) 我是谁（Profile/Region）

要点：确认当前命令行使用的 AWS 身份与区域。

- 命令：`make verify-whoami`
- 通过：`Account=818466672474`，且 Arn 对应你预期的身份（可为 `user/audrey-tf` 或 Toolkit 登录的 session）。
- 截图：终端输出整块（含 `AWS_PROFILE` / `AWS_REGION`）。
![](<demo/0-我是谁(Profile:Region+Python环境).png>)

### 1) Terraform 输出就绪

要点：确保 TF 已部署并且能输出关键资源名/ARN。

- 命令：`make verify-tf-outputs`
- 通过：输出里至少包含 `bronze_bucket` / `silver_bucket` / `queue_url` / `ingest_lambda` / `transform_lambda`。
- 截图：终端 output。
![](<demo/1-Terraform用对了身份+Region.png>)
![](<demo/1-Terraform用对了身份+Region-2.png>)


### 2) S3 事件触发已就绪（bronze → ingest）

要点：S3 Event notification 指向 ingest Lambda，并且 prefix 为 `bronze/`。

- 命令：`make verify-s3-notifications`
- 控制台：S3 → `<bronze_bucket>` → Properties → Event notifications
- 通过：事件存在且目标 ARN 为 ingest。
- 截图：控制台 Event notification 卡片（或终端 table 输出）。
![](<demo/2-S3事件触发已就绪(bronze→LambdaIngest).png>)

### 3) Lambda 存在且可读（ingest / transform）

- 命令：`make verify-lambdas`
- 通过：输出 `OK ingest=...`、`OK transform=...`
- 截图：终端输出；控制台 Lambda → Monitor → Logs
![](<demo/3-Lambda正常(ingest-transform).png>)

### 4) 幂等表（DynamoDB）与 TTL（对象级别）

要点：本项目幂等粒度是 **S3 对象级别**：`s3://bucket/key#etag`，不是 record/event_id 级别。

- 命令：`make verify-ddb`
- 通过：TTL `ENABLED`；scan 能看到 `pk/status` 等字段。
- 截图：终端 TTL 输出 + scan 输出（前几条）。
![](<demo/4-幂等表-DynamoDB-TTL.png>)

### 5) SQS / DLQ 健康

- 命令：`make verify-sqs`
- 通过：主队列消息数接近 0；DLQ 为 0。（消息“最老年龄”属于 CloudWatch 指标，不是 SQS attribute）
- 截图：终端 `get-queue-attributes` 输出； SQS 控制台 Monitoring 图表。
![](<demo/5-SQS-DLQ健康.png>)

### 6) 造数触发 E2E（S3 → ingest → SQS → transform → Silver）

要点：上传一份 Bronze JSONL 触发整条链路。

- 命令：`make verify-seed`（会把本次上传写入 `$(E2E_LAST_SEED_FILE)`）
- 通过：上传成功（终端会打印 `s3://<bronze>/<key>`）
- 截图：终端输出 + S3 控制台里该对象 Key
![](<demo/造数触发E2E(S3-ingest-SQS-transform-Silver).png>)

### 7) Silver 产出 Parquet（等待窗口）

- 命令：`make verify-silver`
- 通过：最近 `$(VERIFY_WINDOW_MINUTES)` 分钟内能观测到 `silver/shipments/` 下新增 parquet。
- 截图：终端 OK 输出；或 S3 控制台显示 parquet 文件列表。
![](<demo/6-造数触发整条链路(S3→ingest→SQS→transform→Silver).png>)

### 8) 幂等验收（同一对象重复触发会被跳过）

要点：为了避免 S3 自动触发干扰，这一步会把对象上传到 `$(E2E_IDEMPOTENCY_PREFIX)/...`（不匹配 `bronze/` 通知），然后手动 invoke ingest 两次，第二次应 `skipped>=1`。

- 命令：`make verify-idempotency`
- 通过：第二次 invoke 输出里 `skipped>=1`，并打印 `OK: second invoke skipped`。
- 截图：终端 first/second 两段输出。
![](<demo/7-幂等验收-profile-key-lambda-invoke.png>)

### 9) Glue / Athena（可选）

前提：`glue_enabled=true`。

- 命令：`make verify-glue`
- 通过：crawler `LastCrawl=SUCCEEDED`；能看到 database 名称。
- 截图：Glue 控制台表结构页 + Athena 查询结果（见下方 “Athena quick queries”）。
![](<demo/8-GlueCatalog-Athena可查询.png>)
![](<demo/Athena.png>)

### 10) GE 质量门禁（可选）

前提：`ge_enabled=true` 且 `ge_workflow_enabled=true`。

- 命令：`make verify-ge`（列出最近执行；手动触发用 `make ge-start`）
- 通过：能看到最近的 executions；或至少 state machine 存在。
- 截图：Step Functions execution 详情（Glue task 绿勾）或终端 list-executions 输出。
![](<demo/9-质量门禁-StepFunctions-GlueGEJob.png>)
![](<demo/step-function-1.png>)
![](<demo/step-function-2.png>)

### 11) CloudWatch Dashboard（可选）

前提：`observability_enabled=true` 且账号允许 `cloudwatch:PutDashboard`。

- 命令：`make verify-observability`
- 通过：输出 `OK dashboard=...`
- 截图：CloudWatch Dashboard 预览页。

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
  - Easiest fix is to allow `sqs:ListQueueTags` (read-only) on your IAM user/role.
  - `python scripts/create_sqs_queue.py --name <project>-<suffix>-events --with-dlq --region us-east-2 --out infra/terraform/envs/dev/queue.auto.tfvars.json`
  - Terraform will auto-load `*.auto.tfvars.json` and skip managing SQS when `existing_queue_url`/`existing_queue_arn` are provided.
- **Attach a DLQ to an existing queue**:
  - `python scripts/ensure_dlq_for_queue.py --queue-url <queue_url> --dlq-name <queue_name>-dlq --region us-east-2`
  - Then add `existing_dlq_url` / `existing_dlq_arn` into `infra/terraform/envs/dev/queue.auto.tfvars.json` (optional; used for outputs/observability).

### Transform dependency

The transform function writes Parquet via the AWS SDK for pandas layer (includes `pyarrow`) configured in `infra/terraform/envs/dev/dev.tfvars:4`.

### Observability (alarms/dashboard)

Terraform can create CloudWatch alarms + a dashboard via `infra/terraform/modules/observability/main.tf:1`, but many restricted dev accounts block:

- `cloudwatch:PutMetricAlarm`
- `cloudwatch:PutDashboard`

In that case, set `observability_enabled = false` in `infra/terraform/envs/dev/dev.tfvars:5` and re-apply (this repo defaults it to `true`).

## License

MIT — see `LICENSE`.
