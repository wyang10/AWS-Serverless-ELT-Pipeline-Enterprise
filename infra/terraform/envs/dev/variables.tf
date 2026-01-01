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

variable "bucket_suffix" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
