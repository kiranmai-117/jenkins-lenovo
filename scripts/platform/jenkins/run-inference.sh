#!/usr/bin/env bash
# Runs inside the 'claude' container (node:22-slim).
# ANTHROPIC_AUTH_TOKEN, ANTHROPIC_API_KEY, and ANTHROPIC_BASE_URL are injected
# via the pod spec — Claude Code routes requests to the Ollama server on localhost.
# Writes /metrics/DONE on completion so collect-metrics.sh stops sampling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

METRICS_DIR="${METRICS_DIR:-/metrics}"
MODEL="${MODEL_NAME:?MODEL_NAME must be set in repo-root config.env}"
PROMPT="Write a Rust program that generates the first 100 prime numbers and save it to output.rs"
CLAUDE_BIN="/npm-global/bin/claude"
DONE_SENTINEL="${METRICS_DIR}/DONE"
OUTPUT_FILE="output.rs"

mkdir -p "${METRICS_DIR}"

echo "=== Claude Code CLI inference via Ollama ==="
echo "Model  : ${MODEL}"
echo "Host   : ${ANTHROPIC_BASE_URL}"
echo "Prompt : ${PROMPT}"
echo "--------------------------------------------"

if [[ ! -x "${CLAUDE_BIN}" ]]; then
    echo "Installing @anthropic-ai/claude-code (first run on this node)..."
    npm install --global @anthropic-ai/claude-code
else
    echo "claude CLI already cached — skipping install."
fi

"${CLAUDE_BIN}" \
    --model "${MODEL}" \
    --output-format text \
    --dangerously-skip-permissions \
    -p "${PROMPT}"

echo "=== Claude Code output (${OUTPUT_FILE}) ==="
cat "${OUTPUT_FILE}"

# Signal collect-metrics.sh to stop sampling now that inference is complete.
touch "${DONE_SENTINEL}"
