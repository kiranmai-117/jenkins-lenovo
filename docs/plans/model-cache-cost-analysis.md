# Model Cache Cost Analysis (EBS/EFS vs Re-download)

## Purpose

Estimate cost trade-offs for downloading a large LLM model repeatedly vs caching it on persistent storage.

This note captures the assumptions and rough-order monthly costs discussed for the current Jenkins GPU workload in `lcp-jenkins`.

## Assumptions

- Model size per pull: `100 GB`
- Region: `us-east-1`
- GPU nodes egress through NAT gateway (verified for current GPU subnet route table)
- NAT data processing: `$0.045/GB`
- EFS Standard storage: `$0.30/GB-month`
- EFS cross-AZ transfer estimate:
  - effective planning value: `$0.02/GB` (round-trip impact approximation)
- EFS cache size considered: `500 Gi`

> Note: Prices are approximate and should be validated against current AWS pricing pages before final budgeting.

## Formulas

- Monthly download volume:
  - `model_size_gb * pulls_per_day * 30`
- NAT processing cost:
  - `monthly_download_gb * 0.045`
- EFS storage cost:
  - `efs_size_gb * 0.30`
- Cross-AZ EFS transfer add-on (scenario dependent):
  - `cross_az_gb * 0.02`

## Scenario A: 4 downloads/day

- Monthly volume: `100 * 4 * 30 = 12,000 GB`

### Re-download each time (no cache)

- NAT processing: `12,000 * 0.045 = $540/month`

### EFS cache (500 Gi)

- Storage baseline: `500 * 0.30 = $150/month`

Cross-AZ variants:

- Best case (same-AZ access): `$150/month`
- Average case (~50% cross-AZ for 12,000 GB):
  - Cross-AZ = `6,000 * 0.02 = $120`
  - Total = `$270/month`
- Worst case (100% cross-AZ for 12,000 GB):
  - Cross-AZ = `12,000 * 0.02 = $240`
  - Total = `$390/month`

### Comparison at 4/day

- No cache via NAT: `$540/month`
- EFS cache range: `$150` to `$390/month`
- Estimated savings with EFS: `$150` to `$390/month` depending on AZ locality

## Scenario B: 2 downloads/day

- Monthly volume: `100 * 2 * 30 = 6,000 GB`

### Re-download each time (no cache)

- NAT processing: `6,000 * 0.045 = $270/month`

### EFS cache (500 Gi)

- Storage baseline: `$150/month`

Cross-AZ variants:

- Best case (same-AZ): `$150/month`
- Average (~50% cross-AZ):
  - Cross-AZ = `3,000 * 0.02 = $60`
  - Total = `$210/month`
- Worst (100% cross-AZ):
  - Cross-AZ = `6,000 * 0.02 = $120`
  - Total = `$270/month`

### Comparison at 2/day

- No cache via NAT: `$270/month`
- EFS cache range: `$150` to `$270/month`
- Interpretation: EFS is cheaper in best/average cases, near break-even in worst case

## Additional notes for future design

- `gp3` EBS (`ReadWriteOnce`) is single-AZ; pod scheduling can fail if workload shifts AZ.
- EFS avoids single-AZ attachment constraints and is easier for cache persistence across node churn.
- If EFS is used, ensure mount targets exist in all relevant AZs to reduce cross-AZ transfer and latency.
- If EBS is used, consider constraining the GPU nodepool to one AZ to keep cache locality stable.
