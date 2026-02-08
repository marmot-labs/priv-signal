#!/usr/bin/env bash
set -euo pipefail

JSON_PATH_1="${1:-tmp/infer-run-1.json}"
JSON_PATH_2="${2:-tmp/infer-run-2.json}"

mkdir -p "$(dirname "$JSON_PATH_1")" "$(dirname "$JSON_PATH_2")"

echo "[bench] run #1"
/usr/bin/time -l mix priv_signal.infer --quiet --json-path "$JSON_PATH_1"

HASH_1=$(jq -r '.summary.flows_hash // "none"' "$JSON_PATH_1")
COUNT_1=$(jq -r '.summary.flow_count // 0' "$JSON_PATH_1")

echo "[bench] run #2"
/usr/bin/time -l mix priv_signal.infer --quiet --json-path "$JSON_PATH_2"

HASH_2=$(jq -r '.summary.flows_hash // "none"' "$JSON_PATH_2")
COUNT_2=$(jq -r '.summary.flow_count // 0' "$JSON_PATH_2")

echo "run1 flow_count=$COUNT_1 flows_hash=$HASH_1"
echo "run2 flow_count=$COUNT_2 flows_hash=$HASH_2"

if [[ "$HASH_1" != "$HASH_2" ]]; then
  echo "[bench] determinism check FAILED: flows_hash mismatch" >&2
  exit 1
fi

echo "[bench] determinism check PASSED"
