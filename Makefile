.PHONY: help test build build-ingest build-transform build-ops-replay build-ops-quality clean tf-init tf-plan tf-apply tf-destroy

PY ?= python3
TF_DIR ?= infra/terraform/envs/dev
BUILD_DIR ?= build
TF_BACKEND_CONFIG ?=
TF_AUTO_APPROVE ?= 0

help:
	@echo "Targets:"
	@echo "  test          Run unit tests"
	@echo "  build         Build lambda zip artifacts into ./$(BUILD_DIR)"
	@echo "  tf-init       terraform init (dev env)"
	@echo "  tf-plan       terraform plan (dev env)"
	@echo "  tf-apply      terraform apply (dev env)"
	@echo "  tf-destroy    terraform destroy (dev env)"

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
