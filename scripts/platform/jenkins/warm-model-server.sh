#!/usr/bin/env bash
# Starts and warms the model server through the runtime's OpenAI-compatible API.
# Server logs are written to /metrics/model-server.log for Jenkins visibility.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

MODEL="${MODEL_NAME:?MODEL_NAME must be set in repo-root config.env}"
MODEL_SOURCE="${MODEL_SERVER_MODEL_ID:-${MODEL}}"
MODEL_SERVER_BASE_URL="${MODEL_SERVER_BASE_URL:-http://localhost:8000/v1}"
MODEL_SERVER_MAX_MODEL_LEN="${MODEL_SERVER_MAX_MODEL_LEN:-16384}"
MODEL_SERVER_GPU_MEMORY_UTILIZATION="${MODEL_SERVER_GPU_MEMORY_UTILIZATION:-0.95}"
READY_URL="${MODEL_SERVER_BASE_URL}/models"
WARMUP_LOG="/metrics/warm-model-server.log"
SERVER_LOG="/metrics/model-server.log"
SERVER_PID_FILE="/tmp/model-server.pid"
LOG_TAIL_PID=""

cleanup_tail() {
    if [[ -n "${LOG_TAIL_PID}" ]]; then
        kill "${LOG_TAIL_PID}" 2>/dev/null || true
        LOG_TAIL_PID=""
    fi
}

trap cleanup_tail EXIT

mkdir -p /metrics
exec > >(tee -a "${WARMUP_LOG}") 2>&1

echo "=== Model Server Warmup at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Model: ${MODEL}"
echo "Model source: ${MODEL_SOURCE}"
echo "Endpoint: ${MODEL_SERVER_BASE_URL}/chat/completions"
echo "Readiness probe: ${READY_URL}"
echo "Max model len: ${MODEL_SERVER_MAX_MODEL_LEN}"
echo "GPU memory util: ${MODEL_SERVER_GPU_MEMORY_UTILIZATION}"

# If a healthy server is already up in this pod, reuse it.
if curl -fsS "${READY_URL}" > /dev/null 2>&1; then
    echo "Status: server already running."
else
    echo "Status: starting vLLM server..."
    : > "${SERVER_LOG}"
    # Start detached so Jenkins warmup step can finish.
    nohup vllm serve "${MODEL_SOURCE}" \
        --host 0.0.0.0 \
        --port 8000 \
        --served-model-name "${MODEL}" \
        --tensor-parallel-size 1 \
        --max-model-len "${MODEL_SERVER_MAX_MODEL_LEN}" \
        --gpu-memory-utilization "${MODEL_SERVER_GPU_MEMORY_UTILIZATION}" \
        --trust-remote-code \
        --max-num-seqs 32 \
        --enable-auto-tool-choice \
        --tool-call-parser qwen3_coder \
        --reasoning-parser qwen3 \
        --speculative-config '{"method":"qwen3_next_mtp","num_speculative_tokens":1}' \
        --language-model-only \
        >> "${SERVER_LOG}" 2>&1 &
    echo $! > "${SERVER_PID_FILE}"
    echo "Started PID: $(cat "${SERVER_PID_FILE}")"

    # Stream logs live only during startup/warmup.
    tail -n +1 -f "${SERVER_LOG}" &
    LOG_TAIL_PID=$!
fi

echo "Waiting for server readiness..."
MAX_ATTEMPTS=90
WAIT_SECONDS=5
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
    if curl -fsS "${READY_URL}" > /dev/null 2>&1; then
        echo "Status: model server is healthy."
        break
    fi
    if [[ -f "${SERVER_PID_FILE}" ]] && ! kill -0 "$(cat "${SERVER_PID_FILE}")" 2>/dev/null; then
        echo "ERROR: model server exited before becoming healthy."
        echo "---- model-server.log ----"
        cat "${SERVER_LOG}" || true
        cleanup_tail
        exit 1
    fi
    echo "[${i}/${MAX_ATTEMPTS}] waiting ${WAIT_SECONDS}s..."
    sleep "${WAIT_SECONDS}"
done

if ! curl -fsS "${READY_URL}" > /dev/null 2>&1; then
    echo "ERROR: model server did not become healthy in time."
    echo "---- model-server.log ----"
    cat "${SERVER_LOG}" || true
    cleanup_tail
    exit 1
fi

echo "=== Available models from ${READY_URL} ==="
curl -fsS "${READY_URL}" | tee /tmp/model-server-models.json

payload=$(cat <<EOF
{"model":"${MODEL}","messages":[{"role":"user","content":"ping"}],"max_tokens":4}
EOF
)


if curl -fsS -X POST "${MODEL_SERVER_BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "${payload}" > /tmp/model-server-warmup.json; then
    echo "Status: warmup request succeeded."
    echo "=== Ping response from model server ==="
    cat /tmp/model-server-warmup.json
    echo "======================================="
else
    echo "Status: warmup request failed."
    cleanup_tail
    exit 1
fi
cleanup_tail
echo "Log file: ${SERVER_LOG}"
