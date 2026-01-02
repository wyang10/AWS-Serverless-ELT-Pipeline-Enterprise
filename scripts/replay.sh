#!/usr/bin/env bash
set -euo pipefail

# Minimal replay wrapper.
#
# Default mode is S3 copy replay (recommended): it re-triggers the normal S3 -> ingest path.
# Usage:
#   scripts/replay.sh <start_iso> <end_iso> [record_prefix]
#
# Examples:
#   scripts/replay.sh 2026-01-01T00:00:00Z 2026-01-02T00:00:00Z bronze/shipments/

START="${1:-}"
END="${2:-}"
PREFIX="${3:-bronze/shipments/}"

if [[ -z "$START" || -z "$END" ]]; then
  echo "Usage: scripts/replay.sh <start_iso> <end_iso> [prefix]"
  echo "Example: scripts/replay.sh 2026-01-01T00:00:00Z 2026-01-02T00:00:00Z bronze/shipments/"
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BRONZE="$(terraform -chdir=infra/terraform/envs/dev output -raw bronze_bucket)"
DEST="bronze/replay/manual/$(date -u +%Y%m%dT%H%M%SZ)"

python3 scripts/replay_via_s3_copy.py \
  --bucket "$BRONZE" \
  --prefix "$PREFIX" \
  --dest-prefix "$DEST" \
  --start "$START" \
  --end "$END"

