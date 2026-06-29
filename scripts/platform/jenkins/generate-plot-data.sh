#!/usr/bin/env bash
# Reads gpu.log and cpu.log and emits per-metric properties files plus an
# HTML summary for publishHTML (Plot Plugin is not available on this Jenkins).
#
# gpu.log columns: timestamp,gpu_util%,mem_bw_util%,mem_used_mib,mem_total_mib,power_w,temp_c
# cpu.log columns: timestamp,user%,nice%,system%,idle%,iowait%,irq%,softirq%
# Usage: generate-plot-data.sh [<metrics-dir>] [<output-dir>]
#   metrics-dir   Source directory containing gpu.log and cpu.log (default: /metrics)
#   output-dir    Destination for plot-*.properties and metrics-summary.html
#                 (default: same as metrics-dir)
set -euo pipefail

METRICS_DIR="${1:-/metrics}"
OUTPUT_DIR="${2:-${METRICS_DIR}}"
RUN_LABEL="$(basename "${METRICS_DIR}")"
GPU_LOG="${METRICS_DIR}/gpu.log"
CPU_LOG="${METRICS_DIR}/cpu.log"

mkdir -p "${OUTPUT_DIR}"

declare -A METRIC_LABELS=(
    [plot-gpu-util-avg.properties]="Avg GPU Utilization"
    [plot-gpu-util-peak.properties]="Peak GPU Utilization"
    [plot-gpu-power-avg.properties]="Avg Power Draw"
    [plot-gpu-temp-peak.properties]="Peak GPU Temperature"
    [plot-gpu-mem-peak.properties]="Peak GPU Memory Used"
    [plot-cpu-active-avg.properties]="Avg CPU Active"
)

declare -A METRIC_UNITS=(
    [plot-gpu-util-avg.properties]="%"
    [plot-gpu-util-peak.properties]="%"
    [plot-gpu-power-avg.properties]="W"
    [plot-gpu-temp-peak.properties]="°C"
    [plot-gpu-mem-peak.properties]="MiB"
    [plot-cpu-active-avg.properties]="%"
)

emit() {
    local file="$1" value="$2"
    printf 'YVALUE=%s\n' "${value}" > "${OUTPUT_DIR}/${file}"
}

if [[ -f "${GPU_LOG}" ]]; then
    emit plot-gpu-util-avg.properties \
        "$(awk -F',' 'NR>1 && NF>1 && $2~/^[0-9]/ {s+=$2; n++} END {printf "%.1f", (n>0 ? s/n : 0)}' "${GPU_LOG}")"

    emit plot-gpu-util-peak.properties \
        "$(awk -F',' 'NR>1 && NF>1 && $2~/^[0-9]/ {if($2>m) m=$2} END {printf "%.1f", m+0}' "${GPU_LOG}")"

    emit plot-gpu-power-avg.properties \
        "$(awk -F',' 'NR>1 && NF>1 && $6~/^[0-9]/ {s+=$6; n++} END {printf "%.1f", (n>0 ? s/n : 0)}' "${GPU_LOG}")"

    emit plot-gpu-temp-peak.properties \
        "$(awk -F',' 'NR>1 && NF>1 && $7~/^[0-9]/ {if($7>m) m=$7} END {printf "%.1f", m+0}' "${GPU_LOG}")"

    emit plot-gpu-mem-peak.properties \
        "$(awk -F',' 'NR>1 && NF>1 && $4~/^[0-9]/ {if($4>m) m=$4} END {printf "%.1f", m+0}' "${GPU_LOG}")"
fi

if [[ -f "${CPU_LOG}" ]]; then
    # Active CPU% = user + system (excludes idle, iowait, irq, softirq)
    emit plot-cpu-active-avg.properties \
        "$(awk -F',' 'NR>1 && NF>1 && $2~/^[0-9]/ {s+=($2+$4); n++} END {printf "%.1f", (n>0 ? s/n : 0)}' "${CPU_LOG}")"
fi

HTML_REPORT="${OUTPUT_DIR}/metrics-summary.html"
{
    echo '<!DOCTYPE html>'
    echo '<html lang="en"><head><meta charset="utf-8">'
    echo '<title>GPU/CPU Metrics</title>'
    echo '<style>'
    echo 'body{font-family:system-ui,sans-serif;margin:2rem;color:#1a1a1a}'
    echo 'h1{font-size:1.25rem;margin-bottom:1rem}'
    echo 'table{border-collapse:collapse;width:100%;max-width:40rem}'
    echo 'th,td{border:1px solid #ccc;padding:.5rem .75rem;text-align:left}'
    echo 'th{background:#f4f4f4}'
    echo 'td.value{font-variant-numeric:tabular-nums}'
    echo '</style></head><body>'
    echo "<h1>Inference Run Metrics (${RUN_LABEL})</h1>"
    echo '<table><thead><tr><th>Metric</th><th>Value</th><th>Unit</th></tr></thead><tbody>'

    shopt -s nullglob
    for prop in "${OUTPUT_DIR}"/plot-*.properties; do
        base="$(basename "${prop}")"
        label="${METRIC_LABELS[${base}]:-${base}}"
        unit="${METRIC_UNITS[${base}]:-}"
        value="$(grep -E '^YVALUE=' "${prop}" | cut -d= -f2-)"
        printf '<tr><td>%s</td><td class="value">%s</td><td>%s</td></tr>\n' \
            "${label}" "${value}" "${unit}"
    done
    shopt -u nullglob

    echo '</tbody></table></body></html>'
} > "${HTML_REPORT}"

echo "Metrics data written to ${OUTPUT_DIR}:"
ls -1 "${OUTPUT_DIR}"/plot-*.properties "${HTML_REPORT}" 2>/dev/null || echo "(none generated)"
