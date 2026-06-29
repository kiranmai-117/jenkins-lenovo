#!/usr/bin/env bash
# Runs selected coding harness as a lightweight preflight inference check.
# Writes METRICS_DIR/DONE on exit so collect-metrics.sh stops sampling.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

HARNESS="${AGENT_HARNESS:-claude}"
MODEL="${MODEL_NAME:?MODEL_NAME must be set in repo-root config.env}"
MODEL_BASE_URL="${MODEL_SERVER_BASE_URL:-http://localhost:8000/v1}"
MODEL_SERVER_PROVIDER="${MODEL_SERVER_PROVIDER:-vllm}"
METRICS_DIR="${METRICS_DIR:-/metrics/${HARNESS}}"
DONE_SENTINEL="${METRICS_DIR}/DONE"
CLAUDE_BIN="/npm-global/bin/claude"
OPENCODE_BIN="/npm-global/bin/opencode"
PI_BIN="/npm-global/bin/pi"

mkdir -p "${METRICS_DIR}"
trap 'touch "${DONE_SENTINEL}"' EXIT

case "${HARNESS}" in
    claude)
        PROMPT="Print exactly: claude-inference-ok"
        echo "=== Claude Code preflight inference ==="
        if [[ ! -x "${CLAUDE_BIN}" ]]; then
            echo "Installing @anthropic-ai/claude-code (first run on this node)..."
            npm install --global @anthropic-ai/claude-code
        fi
        export ANTHROPIC_BASE_URL="${MODEL_BASE_URL}"
        export ANTHROPIC_AUTH_TOKEN="dummy"
        export ANTHROPIC_API_KEY=""
        "${CLAUDE_BIN}" --model "${MODEL}" \
            --dangerously-skip-permissions \
            --output-format text \
            -p "${PROMPT}" \
            | tee "${METRICS_DIR}/claude-preflight.log"
        ;;
    opencode)
        PROMPT="Print exactly: opencode-inference-ok"
        OPENCODE_CONFIG_FILE="${METRICS_DIR}/opencode.json"
        echo "=== OpenCode preflight inference ==="
        if [[ ! -x "${OPENCODE_BIN}" ]]; then
            echo "Installing opencode-ai (first run on this node)..."
            npm install --global opencode-ai
        fi
        cat > "${OPENCODE_CONFIG_FILE}" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "provider": {
    "${MODEL_SERVER_PROVIDER}": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Model Server (local)",
      "options": {
        "baseURL": "${MODEL_BASE_URL}"
      },
      "models": {
        "${MODEL}": {
          "name": "${MODEL}"
        }
      }
    }
  }
}
EOF
        export OPENCODE_CONFIG="${OPENCODE_CONFIG_FILE}"
        "${OPENCODE_BIN}" run \
            --model "${MODEL_SERVER_PROVIDER}/${MODEL}" \
            --dangerously-skip-permissions \
            "${PROMPT}" \
            | tee "${METRICS_DIR}/opencode-preflight.log"
        ;;
    pi.dev)
        PROMPT="Print exactly: pi-dev-inference-ok"
        echo "=== pi.dev preflight inference ==="
        if [[ ! -x "${PI_BIN}" ]]; then
            echo "Installing @earendil-works/pi-coding-agent (first run on this node)..."
            npm install --global --ignore-scripts @earendil-works/pi-coding-agent
        fi
        PI_MODELS_DIR="${HOME}/.pi/agent"
        PI_MODELS_FILE="${PI_MODELS_DIR}/models.json"
        mkdir -p "${PI_MODELS_DIR}"
        cat > "${PI_MODELS_FILE}" <<EOF
{
  "providers": {
    "model-server": {
      "baseUrl": "${MODEL_BASE_URL}",
      "api": "openai-completions",
      "apiKey": "\$OPENAI_API_KEY",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "${MODEL}",
          "name": "${MODEL} (model-server)"
        }
      ]
    }
  }
}
EOF
        export OPENAI_API_KEY="${OPENAI_API_KEY:-dummy}"
        "${PI_BIN}" \
            -p "${PROMPT}" \
            --model "${MODEL}" \
            | tee "${METRICS_DIR}/pi-dev-preflight.log"
        ;;
    *)
        echo "ERROR: Unsupported AGENT_HARNESS '${HARNESS}'. Use 'claude', 'opencode', or 'pi.dev'." >&2
        exit 1
        ;;
esac
