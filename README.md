<!--
 * @Author: Audrey Yang 97855340+wyang10@users.noreply.github.com
 * @Date: 2026-01-02 00:03:56
 * @LastEditors: Audrey Yang 97855340+wyang10@users.noreply.github.com
 * @LastEditTime: 2026-01-02 02:24:49
 * @FilePath: /AWS-Serverless-ELT-Pipeline-Enterprise/README-1.md
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
-->
# AWS Serverless ELT Pipeline — v2.0 (Enterprise-ready)

> 轻量起步，企业化能力随开随用：**S3 → Lambda → SQS → Lambda → S3(Parquet)**，可选编排、目录、质量门禁与可观测性。

This v2.0 elevates the minimal v1 into a **production-ready, enterprise-style** framework:
- **Orchestration (optional):** EventBridge → Step Functions → Glue Job (+ optional **Great Expectations** gate)
- **Catalog / Query (optional):** Glue Data Catalog + Crawler + Athena tables for **silver/** Parquet
- **Replay / Recovery:** `replay` & `redrive` scripts for backfill and poison-message recovery
- **Idempotency:** Object-level dedup via DynamoDB TTL (Powertools Idempotency)
- **CI/CD:** GitHub Actions CI (pytest + terraform fmt) + manual Terraform plan/apply (supports keys/OIDC)

---

## 🧩 Architecture

```

S3 (bronze/*.jsonl)
  └─(ObjectCreated)
     Lambda ingest (Powertools logging/metrics + DynamoDB idempotency)
        └─ SQS (events) ──(event source mapping)──> Lambda transform (Parquet)
              └─ DLQ (optional)
                                └─ S3 (silver/*.parquet) ──> (optional) Glue Catalog & Athena

```

**No VPC / EC2 / API Gateway required** for the minimal path. API Gateway can be added later for sync APIs if needed.

---

## 🔁 v1 vs v2.0

| Aspect | v1 (Minimal) | v2.0 (Enterprise-ready) |
|---|---|---|
| Pipeline | S3→Lambda→SQS→Lambda→S3 | Same + Step Functions orchestration |
| Storage | JSONL → Parquet | Parquet + Glue tables for Athena |
| Idempotency | DDB object-level lock | Powertools Idempotency (DynamoDB TTL) + replay/backfill |
| Replay / DLQ | Manual | `scripts/replay.sh`, `scripts/redrive.sh` |
| Observability | Logs only | (optional) CloudWatch Dashboards + Alarms |
| CI/CD | Manual apply | GitHub Actions CI + manual terraform plan/apply (keys/OIDC) |
| DQ | – | Glue Job + optional Great Expectations gate |

---

## 🌟 What this framework gives you

- **🚀 One-command deploy**: Terraform modules + per-env toggles，支持 GitHub Actions OIDC。
- **🧱 Robust by design**: 对象级幂等、SQS 局部批失败、DLQ redrive、可回放。
- **⚙️ Easy extensibility**: `make scaffold DATASET=<name>` 生成配置/处理器/DQ 模板/样例。
- **📊 Built-in observability**: (可选) CloudWatch Dashboards & Alarms。
- **🔍 Query-ready**: (可选) Glue Catalog + Crawler + Athena 表。
- **✅ Quality gate**: (可选) GE 质量门禁（Glue Job 内运行，Step Functions 编排）。

---

## 📁 Repo Layout

```
repo-root/
├─ README.md
├─ ROADMAP.md
├─ Makefile
├─ templates/                   # scaffolding blueprints
├─ scripts/
│  ├─ gen_fake_events.py
│  ├─ replay_from_s3.py         # S3→SQS 直推 (需要 sqs:SendMessage)
│  ├─ replay.sh                 # S3 copy 到新的 bronze/ 前缀（推荐，无需 SQS 发信权限）
│  ├─ redrive.sh                # SQS 原生 redrive
│  └─ scaffold.sh               # 生成 dataset 骨架
├─ configs/                     # 每个 dataset 的元配置
├─ dq/                          # 轻量 DQ 规则（或映射到 GE）
├─ data_samples/                # 样例 JSON/JSONL
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
│     ├─ init.py
│     ├─ schemas.py
│     └─ utils.py
└─ infra/
└─ terraform/
├─ backend/backend.hcl
├─ modules/
│  ├─ storage/            # S3 bronze/silver, notifications
│  ├─ queue/              # SQS + DLQ
│  ├─ lambdas/            # ingest / transform
│  ├─ ddb/                # idempotency table (+ TTL)
│  ├─ catalog/            # Glue DB + Crawler
│  ├─ glue_job/           # Compaction / GE runner
│  ├─ workflow_ops/       # EventBridge + Step Functions
│  └─ observability/      # Dashboards + Alarms
└─ envs/
└─ dev/
├─ main.tf
├─ dev.tfvars       # toggles: glue/ge/ops/observability
└─ *.auto.tfvars.json  # （可选）注入外部 SQS/ARN 等

```

---

## 🧰 Prereqs

- Python **3.11+**
- Terraform **1.6+**
- AWS credentials for a **dev** account (region 默认 `us-east-2`)
- (Optional) Docker

---

## ⚡ Quickstart

> 默认区域：`us-east-2`。如果你的组织限制 CloudWatch `PutMetricAlarm/PutDashboard`，先把 `observability_enabled=false`（见下文）。

```bash
# 0) Setup
python3 -m venv .venv && source .venv/bin/activate
python -m pip install -U pip
python -m pip install -r requirements-dev.txt
export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2
aws sts get-caller-identity   # 确认 Account/Arn

# 1) Build Lambda artifacts
make build

# 2) Terraform init + apply
make tf-init
TF_AUTO_APPROVE=1 make tf-apply

Upload a small seed to trigger the pipeline:

BRONZE=$(terraform -chdir=infra/terraform/envs/dev output -raw bronze_bucket)
python3 scripts/gen_fake_events.py --type shipments --count 50 --format jsonl --out /tmp/shipments.jsonl
aws s3 cp /tmp/shipments.jsonl "s3://$BRONZE/bronze/shipments/manual/shipments-$(date -u +%Y%m%dT%H%M%SZ).jsonl"

Check silver outputs:

SILVER=$(terraform -chdir=infra/terraform/envs/dev output -raw silver_bucket)
aws s3 ls "s3://$SILVER/silver/shipments/" --recursive | tail


⸻

✅ E2E Verification (one-liners)

# Who am I / region pinned
make verify-whoami

# Terraform outputs exist
make verify-tf-outputs

# S3 notifications wired (bronze -> ingest)
make verify-s3-notifications

# Lambdas reachable
make verify-lambdas

# DDB idempotency table + TTL
make verify-ddb

# SQS health + (optional) DLQ
make verify-sqs

# Seed end-to-end and verify silver
make verify-seed && make verify-silver

# Idempotency: same object twice → second invoke skipped>=1
make verify-idempotency

# End to End Validation
make verify-e2e

如果你新插入的图片比如 `![](demo/1.png)` 显示不出来，通常是下面原因之一：

- 文件路径不对：GitHub 对路径大小写敏感；而且 `demo/1.png` 必须真的存在（本 repo 里默认是 `demo/0-1.png`、`demo/dataset-scaffold.png` 这类文件名）。
- 图片还没被 git 跟踪：本地能看到但没 `git add` / `git commit` / `git push`，GitHub 上当然不会有。
- 文件名有空格/括号/中文：用 `![](<demo/你的文件名 (1).png>)` 这种写法更稳。

建议先跑一键版（会依次执行多步 CLI 验证 + 造数 + 等待 Silver）：

- `make verify-e2e`

![](<demo/0-1.png>)
![](<demo/0-2.png>)

⸻

🧪 Idempotency Model
	•	Scope: S3 object-level (bucket/key#etag)
	•	Store: DynamoDB with TTL (Powertools Idempotency)
	•	SQS consumer: partial batch failure + DLQ redrive 脚本

⸻

📚 Catalog & Query (optional)

Enable Glue DB + Crawler（并供 Athena 查询）：

1. infra/terraform/envs/dev/dev.tfvars：

glue_enabled = true
# glue_silver_prefix = "silver/"
# glue_table_prefix  = "silver_"

2. 部署：

TF_AUTO_APPROVE=1 make tf-apply
make glue-crawler-start
make glue-crawler-status

Then query in Athena:

SELECT dt, shipment_id, origin, destination, carrier, weight_kg, event_time
FROM "<glue_db>".silver
WHERE record_type='shipments'
ORDER BY dt DESC, event_time DESC
LIMIT 20;


⸻

🧵 Step Functions & Quality Gate (optional)
	•	Ops workflow（replay+quality polling）：modules/workflow_ops
	•	Great Expectations：在 Glue Job 内跑（容器化依赖更稳定），由 Step Functions 触发

Enabling flags in dev.tfvars（按需）：

ops_enabled           = true
ge_enabled            = true
ge_workflow_enabled   = true
# ge_emit_events_from_transform = true   # transform 成功后发 EventBridge 触发 GE
# ge_eventbridge_enabled        = true

Run:

make ops-start && make ops-status && make ops-history
make ge-start GE_RECORD_TYPE=shipments GE_DT=2025-12-31 GE_RESULT_PREFIX=ge/results
make ge-status


⸻

🧯 Replay / Recovery
	•	S3-copy replay（推荐）：无需 sqs:SendMessage，触发同一条 S3→ingest→SQS 路径。
	./scripts/replay.sh 2026-01-01T00:00:00Z 2026-01-02T00:00:00Z bronze/shipments/
	•	Direct SQS replay：需要队列上的 sqs:SendMessage。
	python3 scripts/replay_from_s3.py --bucket "$BRONZE" --prefix bronze/shipments/ --queue-url "$(terraform -chdir=infra/terraform/envs/dev output -raw queue_url)"
	•	DLQ redrive（SQS 原生）：
	./scripts/redrive.sh

⸻

🛡️ IAM / Org Gotchas
	•	CloudWatch：许多组织限制 cloudwatch:PutMetricAlarm / cloudwatch:PutDashboard
→ 设置 observability_enabled=false 再部署。
	•	SQS Tag 权限：如果缺 sqs:ListQueueTags/TagQueue，Terraform refresh/create 可能报错
→ 预创建队列并写入 *.auto.tfvars.json（让 TF 只引用，不管理）。
	•	IAM Role 命名/Tag 限制：用 iam_name_prefix 统一前缀，并禁用 IAM/SQS tag（本 repo 已默认关闭）。

⸻

🧱 CI/CD (GitHub Actions)
	•	.github/workflows/ci.yml：pytest + terraform fmt -check
	•	.github/workflows/terraform-manual.yml：手动 plan/apply/destroy（OIDC 首选；无明文密钥）

Secrets:
	•	OIDC：AWS_ROLE_TO_ASSUME
	•	Keys（如需）：AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY（可选 AWS_SESSION_TOKEN）
	•	可选：TF_BACKEND_HCL（远端 state 配置；不提供时限制 apply/destroy）

⸻

🧪 Dataset Scaffold

快速生成一个新数据集骨架：

make scaffold DATASET=ups_shipping
# 将生成：
#   configs/ups_shipping.yaml
#   lambdas/transform/ups_shipping/handler.py
#   dq/ups_shipping/rules.yaml
#   data_samples/ups_shipping/sample.jsonl

调整 configs/<dataset>.yaml（prefix/idempotency_key/output columns），实现 handler 映射逻辑，即可接入。

⸻

🧹 Cleanup

S3 必须先清空再 destroy：

TF_AUTO_APPROVE=1 make tf-destroy || true

BRONZE=$(terraform -chdir=infra/terraform/envs/dev output -raw bronze_bucket)
SILVER=$(terraform -chdir=infra/terraform/envs/dev output -raw silver_bucket)
aws s3 rm "s3://$BRONZE" --recursive || true
aws s3 rm "s3://$SILVER" --recursive || true

TF_AUTO_APPROVE=1 make tf-destroy


⸻

🗺️ Changelog v2.0
	1.	触发编排：EventBridge → Step Functions（DQ 阶段），Task 跑 Glue Job（可选接 GE）
	2.	可查询终点：注册 Glue Catalog + Athena 表（silver/*.parquet）
	3.	回放闭环：`scripts/replay.sh` / `scripts/replay_from_s3.py` + `scripts/redrive.sh`（DLQ → 主队列）
	4.	幂等细节：对象级幂等（S3 bucket/key#etag），Powertools Idempotency + DynamoDB TTL
	5.	CI/CD：GitHub Actions（pytest + terraform fmt；手动触发 terraform plan/apply；支持 keys/OIDC）

⸻

📄 blurb 

- AWS Serverless ELT Pipeline (v2.0 / Enterprise) — S3 → Lambda → SQS → Lambda → S3 (Parquet)
- Added Step Functions orchestration, Glue Data Catalog/Athena, and a GE data-quality gate.
- Implemented DynamoDB-based idempotency (TTL), DLQ/redrive & replay tooling, and GitHub Actions CI/CD via OIDC.
- Production-ready, extensible template: per-dataset scaffold, observable, and recovery-friendly.

⸻

License

MIT
