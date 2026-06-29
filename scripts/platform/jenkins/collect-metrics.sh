#!/usr/bin/env bash
# Runs in the 'ollama' container alongside the inference.
# Samples GPU utilization via nvidia-smi and CPU usage via /proc/stat
# every second until the inference container writes METRICS_DIR/DONE.
#
# Usage: collect-metrics.sh [--metrics-dir <path>]
#   --metrics-dir   Directory for gpu.log, cpu.log, and the DONE sentinel.
#                   Defaults to METRICS_DIR env var, then /metrics.
# Datadog (optional):
#   ENABLE_DD_METRICS=true to enable exports
#   DD_API_KEY, DD_SITE (default: datadoghq.com)
set -euo pipefail

METRICS_DIR="${METRICS_DIR:-/metrics}"
ENABLE_DD_METRICS="${ENABLE_DD_METRICS:-false}"
DD_SITE="${DD_SITE:-datadoghq.com}"
DD_API_URL="https://api.${DD_SITE}/api/v1/series"
RUN_TYPE="${RUN_TYPE:-agent}"
PROJECT_TAG="${BITBUCKET_PROJECT:-unknown}"
REPO_TAG="${BITBUCKET_REPO:-unknown}"
HARNESS_TAG="${AGENT_HARNESS:-unknown}"
MODEL_TAG="${MODEL_NAME:-unknown}"
BRANCH_TAG="${BRANCH_NAME:-unknown}"
JOB_TAG="${JOB_NAME:-unknown}"
BUILD_TAG="${BUILD_NUMBER:-unknown}"
DD_TAGS="project:${PROJECT_TAG},repo:${REPO_TAG},harness:${HARNESS_TAG},model:${MODEL_TAG},branch:${BRANCH_TAG},jenkins_job:${JOB_TAG},build_number:${BUILD_TAG},run_type:${RUN_TYPE}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --metrics-dir)
            METRICS_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--metrics-dir <path>]" >&2
            exit 1
            ;;
    esac
done

GPU_LOG="${METRICS_DIR}/gpu.log"
CPU_LOG="${METRICS_DIR}/cpu.log"
DONE_SENTINEL="${METRICS_DIR}/DONE"
SAMPLE_INTERVAL_SECONDS=1
MAX_WAIT_SECONDS=1800

mkdir -p "${METRICS_DIR}"
# Remove any stale sentinel from a previous run so the wait loop does not
# exit immediately on a reused or locally-tested metrics directory.
rm -f "${DONE_SENTINEL}"

dd_emit_metric() {
    local metric="$1"
    local value="$2"
    local ts="$3"
    [[ "${ENABLE_DD_METRICS}" == "true" ]] || return 0
    [[ -n "${DD_API_KEY:-}" ]] || return 0
    [[ -n "${value}" ]] || return 0

    local payload
    payload=$(cat <<EOF
{"series":[{"metric":"${metric}","points":[[${ts},${value}]],"type":"gauge","tags":["${DD_TAGS//,/\",\"}"]}]}
EOF
)
    curl -sS -X POST "${DD_API_URL}" \
        -H "Content-Type: application/json" \
        -H "DD-API-KEY: ${DD_API_KEY}" \
        -d "${payload}" >/dev/null 2>&1 || true
}

# CSV header for the GPU log.
GPU_FIELDS="utilization.gpu,utilization.memory,memory.used,memory.total,power.draw,temperature.gpu"
echo "timestamp,gpu_util%,mem_bw_util%,mem_used_mib,mem_total_mib,power_w,temp_c" > "${GPU_LOG}"

echo "=== GPU + CPU metrics collection started at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="

# GPU: poll nvidia-smi once per interval with a fixed set of useful fields.
# nvidia-smi is expected in the model-server container image/runtime.
(
    while [[ ! -f "${DONE_SENTINEL}" ]]; do
        ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        row=$(nvidia-smi \
            --query-gpu="${GPU_FIELDS}" \
            --format=csv,noheader,nounits 2>/dev/null | head -1 | tr -d ' ')
        echo "${ts},${row}" >> "${GPU_LOG}"
        epoch_ts=$(date -u +%s)
        IFS=',' read -r gpu_util mem_bw mem_used mem_total power temp <<< "${row}"
        dd_emit_metric "coding_agent.gpu.utilization_pct" "${gpu_util:-0}" "${epoch_ts}"
        dd_emit_metric "coding_agent.gpu.mem_bw_util_pct" "${mem_bw:-0}" "${epoch_ts}"
        dd_emit_metric "coding_agent.gpu.mem_used_mib" "${mem_used:-0}" "${epoch_ts}"
        dd_emit_metric "coding_agent.gpu.mem_total_mib" "${mem_total:-0}" "${epoch_ts}"
        dd_emit_metric "coding_agent.gpu.power_w" "${power:-0}" "${epoch_ts}"
        dd_emit_metric "coding_agent.gpu.temp_c" "${temp:-0}" "${epoch_ts}"
        sleep "${SAMPLE_INTERVAL_SECONDS}"
    done
) &
GPU_PID=$!

# CPU: read /proc/stat, compute utilisation % between samples.
(
    read_cpu_stats() {
        grep '^cpu ' /proc/stat | awk '{print $2,$3,$4,$5,$6,$7,$8}'
    }

    prev=$(read_cpu_stats)
    echo "timestamp,user%,nice%,system%,idle%,iowait%,irq%,softirq%" > "${CPU_LOG}"

    while true; do
        sleep "${SAMPLE_INTERVAL_SECONDS}"
        curr=$(read_cpu_stats)
        ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        awk -v prev="${prev}" -v curr="${curr}" -v ts="${ts}" 'BEGIN {
            split(prev, p); split(curr, c)
            user    = c[1]-p[1]; nice = c[2]-p[2]; sys  = c[3]-p[3]
            idle    = c[4]-p[4]; iow  = c[5]-p[5]; irq  = c[6]-p[6]
            softirq = c[7]-p[7]
            total   = user+nice+sys+idle+iow+irq+softirq
            if (total == 0) total = 1
            printf "%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f\n",
                ts, 100*user/total, 100*nice/total, 100*sys/total,
                100*idle/total, 100*iow/total, 100*irq/total, 100*softirq/total
        }' >> "${CPU_LOG}"
        epoch_ts=$(date -u +%s)
        cpu_active=$(awk -F',' 'END{if(NR>1) printf "%.1f", ($2+$4); else print "0"}' "${CPU_LOG}")
        cpu_idle=$(awk -F',' 'END{if(NR>1) printf "%.1f", $5; else print "0"}' "${CPU_LOG}")
        dd_emit_metric "coding_agent.cpu.active_pct" "${cpu_active:-0}" "${epoch_ts}"
        dd_emit_metric "coding_agent.cpu.idle_pct" "${cpu_idle:-0}" "${epoch_ts}"

        prev="${curr}"
    done
) &
CPU_PID=$!

echo "Sampling started (GPU pid=${GPU_PID}, CPU pid=${CPU_PID}). Waiting for ${DONE_SENTINEL}..."

elapsed=0
while [[ ! -f "${DONE_SENTINEL}" ]]; do
    sleep 1
    elapsed=$(( elapsed + 1 ))
    if (( elapsed >= MAX_WAIT_SECONDS )); then
        echo "WARNING: reached max wait of ${MAX_WAIT_SECONDS}s without DONE sentinel." >&2
        break
    fi
done

kill "${GPU_PID}" "${CPU_PID}" 2>/dev/null || true
wait "${GPU_PID}" "${CPU_PID}" 2>/dev/null || true

echo ""
echo "=== Collection stopped at $(date -u +%Y-%m-%dT%H:%M:%SZ) after ${elapsed}s ==="
echo "GPU log  : ${GPU_LOG}  ($(wc -l < "${GPU_LOG}") lines)"
echo "CPU log  : ${CPU_LOG}  ($(wc -l < "${CPU_LOG}") lines)"

# Emit end-of-run aggregates (optional)
end_ts=$(date -u +%s)
gpu_util_avg=$(awk -F',' 'NR>1 && $2~/^[0-9]/ {s+=$2;n++} END {printf "%.1f", (n>0?s/n:0)}' "${GPU_LOG}")
gpu_util_peak=$(awk -F',' 'NR>1 && $2~/^[0-9]/ {if($2>m) m=$2} END {printf "%.1f", m+0}' "${GPU_LOG}")
cpu_active_avg=$(awk -F',' 'NR>1 && $2~/^[0-9]/ {s+=($2+$4);n++} END {printf "%.1f", (n>0?s/n:0)}' "${CPU_LOG}")
dd_emit_metric "coding_agent.inference.duration_s" "${elapsed}" "${end_ts}"
dd_emit_metric "coding_agent.gpu.utilization_avg_pct" "${gpu_util_avg:-0}" "${end_ts}"
dd_emit_metric "coding_agent.gpu.utilization_peak_pct" "${gpu_util_peak:-0}" "${end_ts}"
dd_emit_metric "coding_agent.cpu.active_avg_pct" "${cpu_active_avg:-0}" "${end_ts}"
