.PHONY: help test build build-ingest build-transform build-ops-replay build-ops-quality clean tf-init tf-plan tf-apply tf-destroy ops-start ops-status ops-history glue-crawler-start glue-crawler-status glue-job-start glue-job-status ge-start ge-status ge-history

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
