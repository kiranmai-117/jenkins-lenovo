#!/usr/bin/env bash
set -euo pipefail

# /workspace is the shared pod volume; WORKSPACE is the Jenkins workspace.
if [ -f /workspace/pr-summary.txt ]; then
    echo "=== Pull Requests raised ==="
    cat /workspace/pr-summary.txt
    cp /workspace/pr-summary.txt "${WORKSPACE}/pr-summary.txt"
else
    echo "=== No PRs were raised ==="
fi

[ -d /workspace/logs ] && cp -r /workspace/logs "${WORKSPACE}/agent-logs" || true

if [ -f /metrics/agent/gpu.log ] || [ -f /metrics/agent/cpu.log ]; then
    mkdir -p metrics-artifacts/agent
    scripts/platform/jenkins/generate-plot-data.sh /metrics/agent metrics-artifacts/agent
    cp /metrics/agent/*.log metrics-artifacts/agent/ 2>/dev/null || true
fi

if [ -f "/metrics/${AGENT_HARNESS}/gpu.log" ] || [ -f "/metrics/${AGENT_HARNESS}/cpu.log" ]; then
    mkdir -p "metrics-artifacts/${AGENT_HARNESS}"
    scripts/platform/jenkins/generate-plot-data.sh "/metrics/${AGENT_HARNESS}" "metrics-artifacts/${AGENT_HARNESS}"
    cp "/metrics/${AGENT_HARNESS}/"*.log "metrics-artifacts/${AGENT_HARNESS}/" 2>/dev/null || true
fi
