# v2 Roadmap (Enterprise-ish)

Planned order (low risk → high impact):

1) **EventBridge + Step Functions**
   - Scheduled backfill/replay
   - Orchestrated runs with retries/timeouts
   - Manual approval + notifications (optional)

2) **Glue (Catalog + Crawler + Job)**
   - Catalog tables for Silver Parquet
   - Partition management
   - Batch compaction / repartition

3) **Data Quality (Great Expectations)**
   - Validate Silver outputs as a gate
   - Store validation results in S3 + metrics

4) **EMR (or EMR Serverless)**
   - Large-scale joins/aggregations/historical recompute
   - Workloads too heavy for Lambda/Glue alone

