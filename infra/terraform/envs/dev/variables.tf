variable "project" {
  type    = string
  default = "serverless-elt"
}

variable "region" {
  type    = string
  default = "us-east-2"
}

variable "profile" {
  type    = string
  default = null
}

variable "iam_name_prefix" {
  type        = string
  default     = null
  description = "Optional override for IAM role name prefix; '-<suffix>' will be appended."
}

variable "existing_queue_url" {
  type        = string
  default     = null
  description = "If set (with existing_queue_arn), Terraform will not manage SQS."
}

variable "existing_queue_arn" {
  type        = string
  default     = null
  description = "If set (with existing_queue_url), Terraform will not manage SQS."
}

variable "existing_dlq_url" {
  type        = string
  default     = null
  description = "Optional DLQ URL (for alarms/outputs when using an externally-managed queue)."
}

variable "existing_dlq_arn" {
  type        = string
  default     = null
  description = "Optional DLQ ARN (for alarms/outputs when using an externally-managed queue)."
}

variable "transform_layers" {
  type        = list(string)
  default     = []
  description = "Extra Lambda layers for the transform function (e.g., AWS SDK for pandas layer)."
}

variable "observability_enabled" {
  type    = bool
  default = true
}

variable "alarm_notification_topic_arn" {
  type        = string
  default     = null
  description = "Optional SNS topic ARN for CloudWatch alarm actions."
}

variable "ops_enabled" {
  type    = bool
  default = false
}

variable "ops_workflow_id" {
  type    = string
  default = "ops-replay-and-quality-gate"
}

variable "ops_schedule_enabled" {
  type    = bool
  default = false
}

variable "ops_schedule_expression" {
  type    = string
  default = "rate(1 day)"
}

variable "ops_src_prefix" {
  type    = string
  default = "bronze/shipments/"
}

variable "ops_dest_prefix_base" {
  type    = string
  default = "bronze/replay/scheduled"
}

variable "ops_window_hours" {
  type    = number
  default = 24
}

variable "ops_record_type" {
  type    = string
  default = "shipments"
}

variable "ops_min_parquet_objects" {
  type    = number
  default = 1
}

variable "ops_poll_interval_seconds" {
  type    = number
  default = 30
}

variable "ops_max_attempts" {
  type    = number
  default = 20
}

variable "glue_enabled" {
  type    = bool
  default = false
}

variable "glue_database_name" {
  type        = string
  default     = null
  description = "Glue database name for Silver tables. If null, a sanitized name derived from project will be used."
}

variable "glue_crawler_name" {
  type        = string
  default     = null
  description = "Glue crawler name. If null, a name derived from project will be used."
}

variable "glue_silver_prefix" {
  type    = string
  default = "silver/"
}

variable "glue_table_prefix" {
  type    = string
  default = ""
}

variable "glue_recrawl_behavior" {
  type    = string
  default = "CRAWL_NEW_FOLDERS_ONLY"
}

variable "glue_job_enabled" {
  type    = bool
  default = false
}

variable "glue_job_name" {
  type    = string
  default = null
}

variable "glue_job_script_key" {
  type    = string
  default = "glue/scripts/compact_silver.py"
}

variable "ge_enabled" {
  type    = bool
  default = false
}

variable "ge_job_name" {
  type        = string
  default     = null
  description = "Glue job name for GE validation. If null, a name derived from project will be used."
}

variable "ge_job_script_key" {
  type    = string
  default = "glue/scripts/ge_validate_silver.py"
}

variable "ge_additional_python_modules" {
  type    = string
  default = "great-expectations==0.18.21"
}

variable "ge_workflow_enabled" {
  type    = bool
  default = false
}

variable "ge_workflow_id" {
  type    = string
  default = "ge-quality-gate"
}

variable "ge_eventbridge_enabled" {
  type    = bool
  default = false
}

variable "ge_event_source" {
  type    = string
  default = "serverless-elt.transform"
}

variable "ge_event_detail_type" {
  type    = string
  default = "silver_partition_ready"
}

variable "ge_emit_events_from_transform" {
  type    = bool
  default = false
}

variable "ge_event_bus_name" {
  type    = string
  default = "default"
}

variable "ge_notification_topic_arn" {
  type        = string
  default     = null
  description = "Optional SNS topic ARN for GE gate failures (falls back to alarm_notification_topic_arn if null)."
}

variable "ge_quarantine_enabled" {
  type        = bool
  default     = false
  description = "If true, the GE gate writes a failure marker under ge_quarantine_prefix."
}

variable "ge_quarantine_prefix" {
  type        = string
  default     = "silver/_quarantine/ge"
  description = "S3 prefix (within silver bucket) to write GE failure markers."
}

variable "bucket_suffix" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
