#!/usr/bin/env bash
# Exports run-level coding-agent metrics (tokens, throughput, run health) to Datadog.
set -euo pipefail

WORKSPACE_DIR="${1:-${WORKSPACE:-.}}"
ENABLE_DD_METRICS="${ENABLE_DD_METRICS:-false}"
DD_SITE="${DD_SITE:-datadoghq.com}"
DD_API_URL="https://api.${DD_SITE}/api/v1/series"

PROJECT_TAG="${BITBUCKET_PROJECT:-unknown}"
HARNESS_TAG="${AGENT_HARNESS:-unknown}"
MODEL_TAG="${MODEL_NAME:-unknown}"
BRANCH_TAG="${BRANCH_NAME:-unknown}"
JOB_TAG="${JOB_NAME:-unknown}"
BUILD_TAG="${BUILD_NUMBER:-unknown}"

if [[ "${ENABLE_DD_METRICS}" != "true" ]]; then
    echo "Datadog export disabled (ENABLE_DD_METRICS!=true)."
    exit 0
fi

if [[ -z "${DD_API_KEY:-}" ]]; then
    echo "Datadog export skipped (DD_API_KEY not set)."
    exit 0
fi

dd_emit_metric() {
    local metric="$1"
    local value="$2"
    local ts="$3"
    local repo_tag="$4"
    local run_type="${5:-agent}"
    [[ -n "${value}" ]] || return 0
    local tags="project:${PROJECT_TAG},repo:${repo_tag},harness:${HARNESS_TAG},model:${MODEL_TAG},branch:${BRANCH_TAG},jenkins_job:${JOB_TAG},build_number:${BUILD_TAG},run_type:${run_type}"
    local payload
    payload=$(cat <<EOF
{"series":[{"metric":"${metric}","points":[[${ts},${value}]],"type":"gauge","tags":["${tags//,/\",\"}"]}]}
EOF
)
    curl -sS -X POST "${DD_API_URL}" \
        -H "Content-Type: application/json" \
        -H "DD-API-KEY: ${DD_API_KEY}" \
        -d "${payload}" >/dev/null 2>&1 || true
}

count_prs() {
    local summary_file="$1"
    [[ -f "${summary_file}" ]] || { echo 0; return; }
    awk 'NF>0{n++} END{print n+0}' "${summary_file}"
}

infer_tokens_from_log() {
    local log_file="$1"
    local metric="$2"
    [[ -f "${log_file}" ]] || { echo ""; return; }
    awk -v m="${metric}" '
        BEGIN{IGNORECASE=1}
        {
            if (m=="input" && $0 ~ /input[^0-9]*[0-9]+/) {
                match($0, /input[^0-9]*([0-9]+)/, a); v=a[1]
            } else if (m=="output" && $0 ~ /output[^0-9]*[0-9]+/) {
                match($0, /output[^0-9]*([0-9]+)/, a); v=a[1]
            } else if (m=="reasoning" && $0 ~ /reasoning[^0-9]*[0-9]+/) {
                match($0, /reasoning[^0-9]*([0-9]+)/, a); v=a[1]
            } else if (m=="total" && $0 ~ /total[^0-9]*[0-9]+/) {
                match($0, /total[^0-9]*([0-9]+)/, a); v=a[1]
            } else if (m=="tps" && $0 ~ /(token|tok)[^0-9]*\/[^0-9]*s[^0-9]*[0-9.]+/) {
                match($0, /([0-9]+(\.[0-9]+)?)/, a); v=a[1]
            }
        }
        END{if (v!="") print v}
    ' "${log_file}" | tail -1
}

epoch_now=$(date -u +%s)
agent_logs_root="${WORKSPACE_DIR}/agent-logs"
metrics_root="${WORKSPACE_DIR}/metrics-artifacts/agent"
pr_summary="${WORKSPACE_DIR}/pr-summary.txt"

repo_count=0
if [[ -d "${agent_logs_root}" ]]; then
    while IFS= read -r repo_dir; do
        repo_name="$(basename "${repo_dir}")"
        repo_count=$((repo_count + 1))

        coding_log="${repo_dir}/coding-agent.log"
        opencode_log="${repo_dir}/opencode-output.log"
        gpu_log="${metrics_root}/gpu.log"

        duration_s=""
        if [[ -f "${gpu_log}" ]]; then
            duration_s="$(awk 'END{print (NR>1?NR-1:0)}' "${gpu_log}")"
        fi

        input_tokens="$(infer_tokens_from_log "${coding_log}" "input")"
        output_tokens="$(infer_tokens_from_log "${coding_log}" "output")"
        reasoning_tokens="$(infer_tokens_from_log "${coding_log}" "reasoning")"
        total_tokens="$(infer_tokens_from_log "${coding_log}" "total")"
        tps="$(infer_tokens_from_log "${coding_log}" "tps")"

        [[ -n "${input_tokens}" ]] || input_tokens="$(infer_tokens_from_log "${opencode_log}" "input")"
        [[ -n "${output_tokens}" ]] || output_tokens="$(infer_tokens_from_log "${opencode_log}" "output")"
        [[ -n "${reasoning_tokens}" ]] || reasoning_tokens="$(infer_tokens_from_log "${opencode_log}" "reasoning")"
        [[ -n "${total_tokens}" ]] || total_tokens="$(infer_tokens_from_log "${opencode_log}" "total")"
        [[ -n "${tps}" ]] || tps="$(infer_tokens_from_log "${opencode_log}" "tps")"

        if [[ -z "${tps}" && -n "${output_tokens}" && -n "${duration_s}" && "${duration_s}" -gt 0 ]]; then
            tps="$(awk -v o="${output_tokens}" -v d="${duration_s}" 'BEGIN{printf "%.3f", (d>0?o/d:0)}')"
        fi

        dd_emit_metric "coding_agent.tokens.input" "${input_tokens:-0}" "${epoch_now}" "${repo_name}"
        dd_emit_metric "coding_agent.tokens.output" "${output_tokens:-0}" "${epoch_now}" "${repo_name}"
        dd_emit_metric "coding_agent.tokens.reasoning" "${reasoning_tokens:-0}" "${epoch_now}" "${repo_name}"
        dd_emit_metric "coding_agent.tokens.total" "${total_tokens:-0}" "${epoch_now}" "${repo_name}"
        dd_emit_metric "coding_agent.tokens.per_second" "${tps:-0}" "${epoch_now}" "${repo_name}"
        dd_emit_metric "coding_agent.inference.duration_s" "${duration_s:-0}" "${epoch_now}" "${repo_name}"
    done < <(find "${agent_logs_root}" -mindepth 2 -maxdepth 2 -type d | sort)
fi

pr_count="$(count_prs "${pr_summary}")"
run_success=1
if [[ "${BUILD_RESULT:-SUCCESS}" != "SUCCESS" ]]; then
    run_success=0
fi

dd_emit_metric "coding_agent.run.repo_count" "${repo_count}" "${epoch_now}" "all"
dd_emit_metric "coding_agent.run.pr_count" "${pr_count}" "${epoch_now}" "all"
dd_emit_metric "coding_agent.run.success" "${run_success}" "${epoch_now}" "all"
dd_emit_metric "coding_agent.run.errors" "$(awk -v s="${run_success}" 'BEGIN{print (s==1?0:1)}')" "${epoch_now}" "all"

echo "Datadog run-level export complete (repos=${repo_count}, prs=${pr_count}, success=${run_success})."
