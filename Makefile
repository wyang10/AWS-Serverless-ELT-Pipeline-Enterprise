.PHONY: help test build build-ingest build-transform build-ops-replay build-ops-quality clean tf-init tf-plan tf-apply tf-destroy \
	ops-start ops-status ops-history glue-crawler-start glue-crawler-status glue-job-start glue-job-status ge-start ge-status ge-history \
	verify-whoami verify-tf-outputs verify-s3-notifications verify-lambdas verify-ddb verify-sqs verify-seed verify-silver verify-idempotency \
	verify-glue verify-ge verify-observability verify-e2e profile-audrey-tf scaffold

PY ?= python3
TF_DIR ?= infra/terraform/envs/dev
BUILD_DIR ?= build
TF_BACKEND_CONFIG ?=
TF_AUTO_APPROVE ?= 0
AWS_REGION ?= us-east-2

OPS_SRC_PREFIX ?= bronze/shipments/manual/
OPS_DEST_PREFIX_BASE ?= bronze/replay/manual
OPS_WINDOW_HOURS ?= 24
OPS_RECORD_TYPE ?= shipments
OPS_MIN_PARQUET_OBJECTS ?= 1
OPS_POLL_INTERVAL_SECONDS ?= 30
OPS_MAX_ATTEMPTS ?= 20
OPS_LAST_EXEC_FILE ?= .last_ops_execution

GLUE_RECORD_TYPE ?= shipments
GLUE_DT ?= 2025-12-31
GLUE_SILVER_PREFIX ?= silver
GLUE_OUTPUT_PREFIX ?= silver_compacted
GLUE_LAST_JOB_RUN_FILE ?= .last_glue_job_run

GE_RECORD_TYPE ?= shipments
GE_DT ?= 2025-12-31
GE_SILVER_PREFIX ?= silver
GE_RESULT_PREFIX ?= ge/results
GE_LAST_EXEC_FILE ?= .last_ge_execution

E2E_LAST_SEED_FILE ?= .last_e2e_seed.json
E2E_SEED_PREFIX ?= bronze/shipments/manual/e2e
E2E_IDEMPOTENCY_PREFIX ?= tmp/e2e-idempotency
VERIFY_SLEEP_SECONDS ?= 15
VERIFY_MAX_ATTEMPTS ?= 20
VERIFY_WINDOW_MINUTES ?= 30

help:
	@echo "Targets:"
	@echo "  test          Run unit tests"
	@echo "  build         Build lambda zip artifacts into ./$(BUILD_DIR)"
	@echo "  tf-init       terraform init (dev env)"
	@echo "  tf-plan       terraform plan (dev env)"
	@echo "  tf-apply      terraform apply (dev env)"
	@echo "  tf-destroy    terraform destroy (dev env)"
	@echo "  ops-start     Start Step Functions ops workflow (writes $(OPS_LAST_EXEC_FILE))"
	@echo "  ops-status    Show Step Functions execution status (EXEC_ARN=... optional)"
	@echo "  ops-history   Show recent execution events (EXEC_ARN=... optional)"
	@echo "  glue-crawler-start  Start Glue crawler for Silver"
	@echo "  glue-crawler-status Show Glue crawler status"
	@echo "  glue-job-start      Start Glue compaction job (GLUE_RECORD_TYPE/GLUE_DT/GLUE_OUTPUT_PREFIX)"
	@echo "  glue-job-status     Show last Glue job run status"
	@echo "  ge-start            Start GE quality gate state machine"
	@echo "  ge-status           Show GE execution status (EXEC_ARN=... optional)"
	@echo "  ge-history          Show recent GE execution events"
	@echo "  verify-e2e          Run screenshot-able E2E checks"
	@echo "  profile-audrey-tf   Create/update local AWS profile alias (audrey-tf)"
	@echo "  scaffold       Generate dataset scaffolding (DATASET=ups_shipping)"

test:
	$(PY) -m pytest -q

build: build-ingest build-transform build-ops-replay build-ops-quality

build-ingest:
	rm -rf $(BUILD_DIR)/ingest && mkdir -p $(BUILD_DIR)/ingest
	rm -f $(BUILD_DIR)/ingest.zip
	mkdir -p $(BUILD_DIR)/ingest/lambdas/ingest
	cp -R lambdas/__init__.py $(BUILD_DIR)/ingest/lambdas/__init__.py
	cp -R lambdas/ingest/app.py $(BUILD_DIR)/ingest/lambdas/ingest/app.py
	cp -R lambdas/shared $(BUILD_DIR)/ingest/lambdas/shared
	find $(BUILD_DIR)/ingest -type d -name '__pycache__' -prune -exec rm -rf {} +
	$(PY) -m pip install -r lambdas/ingest/requirements.txt --target $(BUILD_DIR)/ingest --upgrade
	cd $(BUILD_DIR)/ingest && zip -qr ../ingest.zip .

build-transform:
	rm -rf $(BUILD_DIR)/transform && mkdir -p $(BUILD_DIR)/transform
	rm -f $(BUILD_DIR)/transform.zip
	mkdir -p $(BUILD_DIR)/transform/lambdas/transform
	cp -R lambdas/__init__.py $(BUILD_DIR)/transform/lambdas/__init__.py
	cp -R lambdas/transform/app.py $(BUILD_DIR)/transform/lambdas/transform/app.py
	cp -R lambdas/transform/__init__.py $(BUILD_DIR)/transform/lambdas/transform/__init__.py
	cp -R lambdas/shared $(BUILD_DIR)/transform/lambdas/shared
	find $(BUILD_DIR)/transform -type d -name '__pycache__' -prune -exec rm -rf {} +
	cd $(BUILD_DIR)/transform && zip -qr ../transform.zip .

build-ops-replay:
	rm -rf $(BUILD_DIR)/ops_replay && mkdir -p $(BUILD_DIR)/ops_replay
	rm -f $(BUILD_DIR)/ops_replay.zip
	mkdir -p $(BUILD_DIR)/ops_replay/lambdas/workflows/replay
	cp -R lambdas/__init__.py $(BUILD_DIR)/ops_replay/lambdas/__init__.py
	cp -R lambdas/workflows/__init__.py $(BUILD_DIR)/ops_replay/lambdas/workflows/__init__.py
	cp -R lambdas/workflows/replay/__init__.py $(BUILD_DIR)/ops_replay/lambdas/workflows/replay/__init__.py
	cp -R lambdas/workflows/replay/app.py $(BUILD_DIR)/ops_replay/lambdas/workflows/replay/app.py
	cp -R lambdas/shared $(BUILD_DIR)/ops_replay/lambdas/shared
	find $(BUILD_DIR)/ops_replay -type d -name '__pycache__' -prune -exec rm -rf {} +
	cd $(BUILD_DIR)/ops_replay && zip -qr ../ops_replay.zip .

build-ops-quality:
	rm -rf $(BUILD_DIR)/ops_quality && mkdir -p $(BUILD_DIR)/ops_quality
	rm -f $(BUILD_DIR)/ops_quality.zip
	mkdir -p $(BUILD_DIR)/ops_quality/lambdas/workflows/quality
	cp -R lambdas/__init__.py $(BUILD_DIR)/ops_quality/lambdas/__init__.py
	cp -R lambdas/workflows/__init__.py $(BUILD_DIR)/ops_quality/lambdas/workflows/__init__.py
	cp -R lambdas/workflows/quality/__init__.py $(BUILD_DIR)/ops_quality/lambdas/workflows/quality/__init__.py
	cp -R lambdas/workflows/quality/app.py $(BUILD_DIR)/ops_quality/lambdas/workflows/quality/app.py
	cp -R lambdas/shared $(BUILD_DIR)/ops_quality/lambdas/shared
	find $(BUILD_DIR)/ops_quality -type d -name '__pycache__' -prune -exec rm -rf {} +
	cd $(BUILD_DIR)/ops_quality && zip -qr ../ops_quality.zip .

clean:
	rm -rf $(BUILD_DIR)

tf-init:
	cd $(TF_DIR) && terraform init $(if $(TF_BACKEND_CONFIG),-backend-config=$(TF_BACKEND_CONFIG),)

tf-plan:
	cd $(TF_DIR) && terraform plan -var-file=dev.tfvars

tf-apply:
	cd $(TF_DIR) && terraform apply $(if $(filter 1,$(TF_AUTO_APPROVE)),-auto-approve,) -var-file=dev.tfvars

tf-destroy:
	cd $(TF_DIR) && terraform destroy $(if $(filter 1,$(TF_AUTO_APPROVE)),-auto-approve,) -var-file=dev.tfvars

ops-start:
	@set -eu; \
	SM_ARN=$$(terraform -chdir=$(TF_DIR) output -raw ops_state_machine_arn); \
	BRONZE=$$(terraform -chdir=$(TF_DIR) output -raw bronze_bucket); \
	SILVER=$$(terraform -chdir=$(TF_DIR) output -raw silver_bucket); \
	INPUT=$$(BRONZE="$$BRONZE" SILVER="$$SILVER" \
	OPS_SRC_PREFIX="$(OPS_SRC_PREFIX)" OPS_DEST_PREFIX_BASE="$(OPS_DEST_PREFIX_BASE)" \
	OPS_WINDOW_HOURS="$(OPS_WINDOW_HOURS)" OPS_RECORD_TYPE="$(OPS_RECORD_TYPE)" \
	OPS_MIN_PARQUET_OBJECTS="$(OPS_MIN_PARQUET_OBJECTS)" OPS_POLL_INTERVAL_SECONDS="$(OPS_POLL_INTERVAL_SECONDS)" \
	OPS_MAX_ATTEMPTS="$(OPS_MAX_ATTEMPTS)" \
	$(PY) -c 'import json, os; print(json.dumps({ \
	"bronze_bucket": os.environ["BRONZE"], \
	"src_prefix": os.environ["OPS_SRC_PREFIX"], \
	"dest_prefix_base": os.environ["OPS_DEST_PREFIX_BASE"], \
	"window_hours": int(os.environ["OPS_WINDOW_HOURS"]), \
	"silver_bucket": os.environ["SILVER"], \
	"silver_prefix": "silver", \
	"record_type": os.environ["OPS_RECORD_TYPE"], \
	"min_parquet_objects": int(os.environ["OPS_MIN_PARQUET_OBJECTS"]), \
	"poll_interval_seconds": int(os.environ["OPS_POLL_INTERVAL_SECONDS"]), \
	"max_attempts": int(os.environ["OPS_MAX_ATTEMPTS"]), \
	}, separators=(",", ":")))'); \
	TMP=$$(mktemp); \
	aws stepfunctions start-execution --region $(AWS_REGION) --state-machine-arn "$$SM_ARN" --input "$$INPUT" > "$$TMP"; \
	cat "$$TMP"; \
	$(PY) -c 'import json, sys; print(json.load(sys.stdin)["executionArn"])' < "$$TMP" > "$(OPS_LAST_EXEC_FILE)"; \
	rm -f "$$TMP"; \
	echo "Saved executionArn to $(OPS_LAST_EXEC_FILE)"

ops-status:
	@set -eu; \
	EXEC_ARN="$(EXEC_ARN)"; \
	if [ -z "$$EXEC_ARN" ]; then \
		if [ -f "$(OPS_LAST_EXEC_FILE)" ]; then EXEC_ARN=$$(cat "$(OPS_LAST_EXEC_FILE)"); else \
			echo "Missing EXEC_ARN. Run 'make ops-start' or pass EXEC_ARN=arn:aws:states:..."; exit 1; \
		fi; \
	fi; \
	aws stepfunctions describe-execution --region $(AWS_REGION) --execution-arn "$$EXEC_ARN"

ops-history:
	@set -eu; \
	EXEC_ARN="$(EXEC_ARN)"; \
	if [ -z "$$EXEC_ARN" ]; then \
		if [ -f "$(OPS_LAST_EXEC_FILE)" ]; then EXEC_ARN=$$(cat "$(OPS_LAST_EXEC_FILE)"); else \
			echo "Missing EXEC_ARN. Run 'make ops-start' or pass EXEC_ARN=arn:aws:states:..."; exit 1; \
		fi; \
	fi; \
	aws stepfunctions get-execution-history --region $(AWS_REGION) --execution-arn "$$EXEC_ARN" --reverse-order --max-results 30

glue-crawler-start:
	@set -eu; \
	CRAWLER=$$(terraform -chdir=$(TF_DIR) output -raw glue_crawler_name 2>/dev/null || true); \
	if [ -z "$$CRAWLER" ] || [ "$$CRAWLER" = "null" ]; then \
		echo "glue_crawler_name output is empty. Enable Glue crawler (glue_enabled=true) and re-apply."; exit 1; \
	fi; \
	aws glue start-crawler --region $(AWS_REGION) --name "$$CRAWLER"; \
	echo "Started crawler $$CRAWLER"

glue-crawler-status:
	@set -eu; \
	CRAWLER=$$(terraform -chdir=$(TF_DIR) output -raw glue_crawler_name 2>/dev/null || true); \
	if [ -z "$$CRAWLER" ] || [ "$$CRAWLER" = "null" ]; then \
		echo "glue_crawler_name output is empty. Enable Glue crawler (glue_enabled=true) and re-apply."; exit 1; \
	fi; \
	aws glue get-crawler --region $(AWS_REGION) --name "$$CRAWLER" --query 'Crawler.{Name:Name,State:State,LastCrawl:LastCrawl.Status}' --output json

glue-job-start:
	@set -eu; \
	JOB=$$(terraform -chdir=$(TF_DIR) output -raw glue_job_name 2>/dev/null || true); \
	if [ -z "$$JOB" ] || [ "$$JOB" = "null" ]; then \
		echo "glue_job_name output is empty. Enable the job first (glue_job_enabled=true) and re-apply."; exit 1; \
	fi; \
	SILVER=$$(terraform -chdir=$(TF_DIR) output -raw silver_bucket); \
	TMP=$$(mktemp); \
	aws glue start-job-run --region $(AWS_REGION) --job-name "$$JOB" \
	  --arguments "{\"--SILVER_BUCKET\":\"$$SILVER\",\"--SILVER_PREFIX\":\"$(GLUE_SILVER_PREFIX)\",\"--RECORD_TYPE\":\"$(GLUE_RECORD_TYPE)\",\"--DT\":\"$(GLUE_DT)\",\"--OUTPUT_PREFIX\":\"$(GLUE_OUTPUT_PREFIX)\"}" \
	  > "$$TMP"; \
	cat "$$TMP"; \
	RUN_ID=$$($(PY) -c 'import json, sys; print(json.load(sys.stdin)["JobRunId"])' < "$$TMP"); \
	echo "$$RUN_ID" > "$(GLUE_LAST_JOB_RUN_FILE)"; \
	rm -f "$$TMP"; \
	echo "Saved JobRunId to $(GLUE_LAST_JOB_RUN_FILE)"

glue-job-status:
	@set -eu; \
	JOB=$$(terraform -chdir=$(TF_DIR) output -raw glue_job_name 2>/dev/null || true); \
	if [ -z "$$JOB" ] || [ "$$JOB" = "null" ]; then \
		echo "glue_job_name output is empty. Enable the job first (glue_job_enabled=true) and re-apply."; exit 1; \
	fi; \
	if [ ! -f "$(GLUE_LAST_JOB_RUN_FILE)" ]; then \
		echo "Missing $(GLUE_LAST_JOB_RUN_FILE). Run 'make glue-job-start' first."; exit 1; \
	fi; \
	RUN_ID=$$(cat "$(GLUE_LAST_JOB_RUN_FILE)"); \
	aws glue get-job-run --region $(AWS_REGION) --job-name "$$JOB" --run-id "$$RUN_ID" \
	  --query 'JobRun.{Id:Id,JobName:JobName,JobRunState:JobRunState,StartedOn:StartedOn,CompletedOn:CompletedOn,ErrorMessage:ErrorMessage}' --output json

ge-start:
	@set -eu; \
	SM_ARN=$$(terraform -chdir=$(TF_DIR) output -raw ge_state_machine_arn 2>/dev/null || true); \
	if [ -z "$$SM_ARN" ] || [ "$$SM_ARN" = "null" ]; then \
		echo "ge_state_machine_arn output is empty. Enable GE workflow (ge_enabled=true, ge_workflow_enabled=true) and re-apply."; exit 1; \
	fi; \
	SILVER=$$(terraform -chdir=$(TF_DIR) output -raw silver_bucket); \
	INPUT=$$(SILVER="$$SILVER" GE_SILVER_PREFIX="$(GE_SILVER_PREFIX)" GE_RECORD_TYPE="$(GE_RECORD_TYPE)" GE_DT="$(GE_DT)" GE_RESULT_PREFIX="$(GE_RESULT_PREFIX)" \
	$(PY) -c 'import json, os; print(json.dumps({ \
	"silver_bucket": os.environ["SILVER"], \
	"silver_prefix": os.environ["GE_SILVER_PREFIX"], \
	"record_type": os.environ["GE_RECORD_TYPE"], \
	"dt": os.environ["GE_DT"], \
	"result_prefix": os.environ["GE_RESULT_PREFIX"], \
	}, separators=(",", ":")))'); \
	TMP=$$(mktemp); \
	aws stepfunctions start-execution --region $(AWS_REGION) --state-machine-arn "$$SM_ARN" --input "$$INPUT" > "$$TMP"; \
	cat "$$TMP"; \
	$(PY) -c 'import json, sys; print(json.load(sys.stdin)["executionArn"])' < "$$TMP" > "$(GE_LAST_EXEC_FILE)"; \
	rm -f "$$TMP"; \
	echo "Saved executionArn to $(GE_LAST_EXEC_FILE)"

ge-status:
	@set -eu; \
	EXEC_ARN="$(EXEC_ARN)"; \
	if [ -z "$$EXEC_ARN" ]; then \
		if [ -f "$(GE_LAST_EXEC_FILE)" ]; then EXEC_ARN=$$(cat "$(GE_LAST_EXEC_FILE)"); else \
			echo "Missing EXEC_ARN. Run 'make ge-start' or pass EXEC_ARN=arn:aws:states:..."; exit 1; \
		fi; \
	fi; \
	aws stepfunctions describe-execution --region $(AWS_REGION) --execution-arn "$$EXEC_ARN"

ge-history:
	@set -eu; \
	EXEC_ARN="$(EXEC_ARN)"; \
	if [ -z "$$EXEC_ARN" ]; then \
		if [ -f "$(GE_LAST_EXEC_FILE)" ]; then EXEC_ARN=$$(cat "$(GE_LAST_EXEC_FILE)"); else \
			echo "Missing EXEC_ARN. Run 'make ge-start' or pass EXEC_ARN=arn:aws:states:..."; exit 1; \
		fi; \
	fi; \
	aws stepfunctions get-execution-history --region $(AWS_REGION) --execution-arn "$$EXEC_ARN" --reverse-order --max-results 30

profile-audrey-tf:
	@set -eu; \
	$(PY) scripts/setup_profile_alias.py --profile audrey-tf --from default --region $(AWS_REGION) >/dev/null
	@echo "OK: created/updated AWS profile 'audrey-tf' (region $(AWS_REGION))."

verify-whoami:
	@set -eu; \
	echo "AWS_PROFILE=$${AWS_PROFILE:-<default>} AWS_REGION=$(AWS_REGION)"; \
	if [ -n "$${AWS_PROFILE:-}" ]; then \
		if ! aws configure list-profiles | tr -d '\r' | grep -qx "$$AWS_PROFILE"; then \
			echo "AWS profile '$$AWS_PROFILE' not found. Run 'make profile-audrey-tf' or set AWS_PROFILE=818466672474."; exit 1; \
		fi; \
	fi; \
	aws sts get-caller-identity --region $(AWS_REGION)

verify-tf-outputs:
	@set -eu; \
	terraform -chdir=$(TF_DIR) output

verify-s3-notifications:
	@set -eu; \
	BRONZE=$$(terraform -chdir=$(TF_DIR) output -raw bronze_bucket); \
	aws s3api get-bucket-notification-configuration --bucket "$$BRONZE" --region $(AWS_REGION) \
	  --query 'LambdaFunctionConfigurations[].{Arn:LambdaFunctionArn,Events:Events,Prefix:Filter.Key.FilterRules[?Name==`prefix`].Value|[0]}' --output table

verify-lambdas:
	@set -eu; \
	LAMBDA_INGEST=$$(terraform -chdir=$(TF_DIR) output -raw ingest_lambda); \
	LAMBDA_TRANSFORM=$$(terraform -chdir=$(TF_DIR) output -raw transform_lambda); \
	aws lambda get-function --function-name "$$LAMBDA_INGEST" --region $(AWS_REGION) >/dev/null && echo "OK ingest=$$LAMBDA_INGEST"; \
	aws lambda get-function --function-name "$$LAMBDA_TRANSFORM" --region $(AWS_REGION) >/dev/null && echo "OK transform=$$LAMBDA_TRANSFORM"; \
	echo "LogGroups: /aws/lambda/$$LAMBDA_INGEST  /aws/lambda/$$LAMBDA_TRANSFORM"

verify-ddb:
	@set -eu; \
	DDB=$$(terraform -chdir=$(TF_DIR) output -raw idempotency_table_name 2>/dev/null || true); \
	if [ -z "$$DDB" ] || [ "$$DDB" = "null" ]; then \
		DDB=$$(terraform -chdir=$(TF_DIR) state show module.idempotency_table.aws_dynamodb_table.this | awk -F' = ' '/^[[:space:]]*name[[:space:]]+=/{gsub(/"/,"",$$2);print $$2; exit}'); \
	fi; \
	if [ -z "$$DDB" ]; then echo "Could not determine DynamoDB table name. Run TF apply first."; exit 1; fi; \
	echo "$$DDB"; \
	aws dynamodb describe-time-to-live --table-name "$$DDB" --region $(AWS_REGION); \
	aws dynamodb scan --table-name "$$DDB" --max-items 5 --region $(AWS_REGION)

verify-sqs:
	@set -eu; \
	SQS_URL=$$(terraform -chdir=$(TF_DIR) output -raw queue_url); \
	DLQ_URL=$$(terraform -chdir=$(TF_DIR) output -raw dlq_url); \
	aws sqs get-queue-attributes --queue-url "$$SQS_URL" --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible ApproximateNumberOfMessagesDelayed --region $(AWS_REGION); \
	aws sqs get-queue-attributes --queue-url "$$DLQ_URL" --attribute-names ApproximateNumberOfMessages --region $(AWS_REGION)

verify-seed:
	@set -eu; \
	BRONZE=$$(terraform -chdir=$(TF_DIR) output -raw bronze_bucket); \
	TS=$$(date -u +%Y%m%dT%H%M%SZ); \
	KEY="$(E2E_SEED_PREFIX)/shipments_$$TS.jsonl"; \
	$(PY) scripts/gen_fake_events.py --type shipments --count 50 --format jsonl --out /tmp/shipments_e2e.jsonl; \
	aws s3 cp /tmp/shipments_e2e.jsonl "s3://$$BRONZE/$$KEY" --region $(AWS_REGION); \
	ETAG=$$(aws s3api head-object --bucket "$$BRONZE" --key "$$KEY" --query ETag --output text --region $(AWS_REGION) | tr -d '\"'); \
	BRONZE="$$BRONZE" KEY="$$KEY" ETAG="$$ETAG" OUT="$(E2E_LAST_SEED_FILE)" \
	$(PY) -c 'import json, os, pathlib; p=pathlib.Path(os.environ["OUT"]); p.write_text(json.dumps({"bronze_bucket":os.environ["BRONZE"],"key":os.environ["KEY"],"etag":os.environ["ETAG"]}, indent=2)+"\\n")'; \
	echo "Saved $(E2E_LAST_SEED_FILE): s3://$$BRONZE/$$KEY"

verify-silver:
	@set -eu; \
	SILVER=$$(terraform -chdir=$(TF_DIR) output -raw silver_bucket); \
	$(PY) scripts/check_recent_s3_objects.py \
	  --bucket "$$SILVER" \
	  --prefix "silver/shipments/" \
	  --suffix ".parquet" \
	  --region "$(AWS_REGION)" \
	  --window-minutes "$(VERIFY_WINDOW_MINUTES)" \
	  --sleep-seconds "$(VERIFY_SLEEP_SECONDS)" \
	  --max-attempts "$(VERIFY_MAX_ATTEMPTS)"

verify-idempotency:
	@set -eu; \
	LAMBDA_INGEST=$$(terraform -chdir=$(TF_DIR) output -raw ingest_lambda); \
	BRONZE=$$(terraform -chdir=$(TF_DIR) output -raw bronze_bucket); \
	TS=$$(date -u +%Y%m%dT%H%M%SZ); \
	KEY="$(E2E_IDEMPOTENCY_PREFIX)/idempotency_$$TS.jsonl"; \
	echo '{"record_type":"shipments","event_time":"'$$(date -u +%Y-%m-%dT%H:%M:%SZ)'","shipment_id":"e2e_idempotency","origin":"SZX","destination":"SEA","carrier":"UPS","weight_kg":1.0}' > /tmp/idempotency.jsonl; \
	aws s3 cp /tmp/idempotency.jsonl "s3://$$BRONZE/$$KEY" --region $(AWS_REGION); \
	ETAG=$$(aws s3api head-object --bucket "$$BRONZE" --key "$$KEY" --query ETag --output text --region $(AWS_REGION) | tr -d '\"'); \
	printf '{"Records":[{"s3":{"bucket":{"name":"%s"},"object":{"key":"%s","eTag":"%s"}}}]}\n' "$$BRONZE" "$$KEY" "$$ETAG" > /tmp/ingest_event.json; \
	aws lambda invoke --function-name "$$LAMBDA_INGEST" --region $(AWS_REGION) --cli-binary-format raw-in-base64-out --payload file:///tmp/ingest_event.json /tmp/ingest_out_1.json >/dev/null; \
	aws lambda invoke --function-name "$$LAMBDA_INGEST" --region $(AWS_REGION) --cli-binary-format raw-in-base64-out --payload file:///tmp/ingest_event.json /tmp/ingest_out_2.json >/dev/null; \
	echo "first:"; cat /tmp/ingest_out_1.json; echo; \
	echo "second:"; cat /tmp/ingest_out_2.json; echo; \
	$(PY) -c 'import json; o=json.load(open("/tmp/ingest_out_2.json")); skipped=int(o.get("skipped",0)); raise SystemExit(0 if skipped>=1 else 1)' \
	&& echo "OK: second invoke skipped (idempotent)" || (echo "FAIL: expected skipped>=1 on second invoke"; exit 1)

verify-glue:
	@set -eu; \
	CRAWLER=$$(terraform -chdir=$(TF_DIR) output -raw glue_crawler_name 2>/dev/null || true); \
	DB=$$(terraform -chdir=$(TF_DIR) output -raw glue_database_name 2>/dev/null || true); \
	if [ -z "$$CRAWLER" ] || [ "$$CRAWLER" = "null" ]; then echo "Glue not enabled (glue_enabled=true)."; exit 1; fi; \
	aws glue get-crawler --region $(AWS_REGION) --name "$$CRAWLER" --query 'Crawler.{Name:Name,State:State,LastCrawl:LastCrawl.Status}' --output json; \
	echo "database=$$DB"

verify-ge:
	@set -eu; \
	SM_ARN=$$(terraform -chdir=$(TF_DIR) output -raw ge_state_machine_arn 2>/dev/null || true); \
	if [ -z "$$SM_ARN" ] || [ "$$SM_ARN" = "null" ]; then echo "GE workflow not enabled (ge_enabled=true, ge_workflow_enabled=true)."; exit 1; fi; \
	aws stepfunctions list-executions --region $(AWS_REGION) --state-machine-arn "$$SM_ARN" --max-results 5

verify-observability:
	@set -eu; \
	DASH=$$(terraform -chdir=$(TF_DIR) output -raw dashboard_name 2>/dev/null || true); \
	if [ -z "$$DASH" ] || [ "$$DASH" = "null" ]; then echo "Observability disabled or not deployed."; exit 0; fi; \
	aws cloudwatch get-dashboard --region $(AWS_REGION) --dashboard-name "$$DASH" >/dev/null; \
	echo "OK dashboard=$$DASH"

verify-e2e: verify-whoami verify-tf-outputs verify-s3-notifications verify-lambdas verify-ddb verify-sqs verify-seed verify-silver verify-idempotency verify-glue verify-ge verify-observability

scaffold:
	@test -n "$(DATASET)" || (echo "Usage: make scaffold DATASET=ups_shipping" && exit 1)
	@./scripts/scaffold.sh "$(DATASET)"
