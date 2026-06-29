# Datadog Metrics Schema

This document defines custom metric names, tags, and baseline dashboards/alerts
for coding-agent CI runs.

## Global Tags

Apply these tags to all emitted metrics when available:

- `project:<bitbucket_project>`
- `repo:<repo_slug>`
- `harness:<claude|opencode|pi.dev>`
- `model:<ollama_model>`
- `branch:<branch_name>`
- `jenkins_job:<job_name>`
- `build_number:<build_number>`
- `run_type:<agent|preflight>`

## Metrics

### Resource Metrics (sampled, 1s)

- `coding_agent.gpu.utilization_pct` (gauge)
- `coding_agent.gpu.mem_bw_util_pct` (gauge)
- `coding_agent.gpu.mem_used_mib` (gauge)
- `coding_agent.gpu.mem_total_mib` (gauge)
- `coding_agent.gpu.power_w` (gauge)
- `coding_agent.gpu.temp_c` (gauge)
- `coding_agent.cpu.active_pct` (gauge)
- `coding_agent.cpu.idle_pct` (gauge)

### Run-Level Aggregates

- `coding_agent.inference.duration_s` (gauge)
- `coding_agent.gpu.utilization_avg_pct` (gauge)
- `coding_agent.gpu.utilization_peak_pct` (gauge)
- `coding_agent.cpu.active_avg_pct` (gauge)
- `coding_agent.run.success` (gauge: 0 or 1)
- `coding_agent.run.repo_count` (gauge)
- `coding_agent.run.pr_count` (gauge)
- `coding_agent.run.errors` (gauge)

### Token/Throughput Metrics

- `coding_agent.tokens.input` (gauge)
- `coding_agent.tokens.output` (gauge)
- `coding_agent.tokens.reasoning` (gauge)
- `coding_agent.tokens.total` (gauge)
- `coding_agent.tokens.per_second` (gauge)

## Dashboard (Baseline)

Create one dashboard with the following widgets:

1. GPU utilization timeseries by `repo,harness`
2. GPU memory used timeseries by `repo`
3. CPU active timeseries by `repo,harness`
4. Tokens/sec toplist by `repo`
5. Run duration distribution by `harness`
6. Run success ratio by `repo`

## Alert Recommendations

- **Low GPU Utilization During Active Run**
  - Query: `avg(last_10m):avg:coding_agent.gpu.utilization_pct{run_type:agent} by {repo} < 20`
- **Tokens/sec Regression**
  - Query: `avg(last_30m):avg:coding_agent.tokens.per_second{run_type:agent} by {repo,harness} < <baseline>`
- **Run Failure Spike**
  - Query: `sum(last_1h):sum:coding_agent.run.success{*} by {repo} < 1`
- **Long Running Jobs**
  - Query: `avg(last_30m):avg:coding_agent.inference.duration_s{run_type:agent} by {repo} > 1800`
