#!/usr/bin/env bash
set -euo pipefail

MAX_ATTEMPTS=30
WAIT_INTERVAL_SECONDS=5
MODEL_SERVER_BASE_URL="${MODEL_SERVER_BASE_URL:-http://localhost:8000/v1}"
READY_URL="${MODEL_SERVER_BASE_URL}/models"

echo "Waiting for model server to be ready..."

for i in $(seq 1 "${MAX_ATTEMPTS}"); do
    if curl -fsS "${READY_URL}" > /dev/null 2>&1; then
        echo "Model server is ready"
        exit 0
    fi
    echo "[${i}/${MAX_ATTEMPTS}] not ready yet, waiting ${WAIT_INTERVAL_SECONDS}s..."
    sleep "${WAIT_INTERVAL_SECONDS}"
done

echo "ERROR: model server did not become ready after $((MAX_ATTEMPTS * WAIT_INTERVAL_SECONDS))s" >&2
exit 1
