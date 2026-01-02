#!/usr/bin/env bash
set -euo pipefail

DATASET="${1:-}"
if [[ -z "$DATASET" ]]; then
  echo "Usage: scripts/scaffold.sh <dataset_name>"
  echo "Example: scripts/scaffold.sh ups_shipping"
  exit 1
fi

# Normalize dataset to safe folder name (optional)
# Keep underscores and hyphens, replace spaces with underscore
DATASET="${DATASET// /_}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

CONFIG_DIR="$ROOT/configs"
LAMBDA_DIR="$ROOT/lambdas/transform/$DATASET"
DQ_DIR="$ROOT/dq/$DATASET"
SAMPLE_DIR="$ROOT/data_samples/$DATASET"
TEMPLATE_DIR="$ROOT/templates"

mkdir -p "$CONFIG_DIR" "$LAMBDA_DIR" "$DQ_DIR" "$SAMPLE_DIR"

CFG_PATH="$CONFIG_DIR/$DATASET.yaml"
HANDLER_PATH="$LAMBDA_DIR/handler.py"
DQ_PATH="$DQ_DIR/rules.yaml"
SAMPLE_PATH="$SAMPLE_DIR/sample.jsonl"

if [[ -f "$CFG_PATH" ]]; then
  echo "Config exists: $CFG_PATH"
else
  sed "s/{{DATASET}}/$DATASET/g" "$TEMPLATE_DIR/dataset.yaml" > "$CFG_PATH"
  echo "Created: $CFG_PATH"
fi

if [[ -f "$HANDLER_PATH" ]]; then
  echo "Handler exists: $HANDLER_PATH"
else
  sed "s/{{DATASET}}/$DATASET/g" "$TEMPLATE_DIR/transform_handler.py" > "$HANDLER_PATH"
  echo "Created: $HANDLER_PATH"
fi

if [[ -f "$DQ_PATH" ]]; then
  echo "DQ rules exists: $DQ_PATH"
else
  sed "s/{{DATASET}}/$DATASET/g" "$TEMPLATE_DIR/dq_rules.yaml" > "$DQ_PATH"
  echo "Created: $DQ_PATH"
fi

if [[ -f "$SAMPLE_PATH" ]]; then
  echo "Sample exists: $SAMPLE_PATH"
else
  sed "s/{{DATASET}}/$DATASET/g" "$TEMPLATE_DIR/sample.jsonl" > "$SAMPLE_PATH"
  echo "Created: $SAMPLE_PATH"
fi

echo ""
echo "✅ Scaffold complete for dataset: $DATASET"
echo "Next:"
echo "  1) Edit $CFG_PATH (idempotency_key, prefixes, output schema)"
echo "  2) Implement mapping in $HANDLER_PATH"
echo "  3) (Optional) Adjust $DQ_PATH"

