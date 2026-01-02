variable "enabled" {
  type    = bool
  default = true
}

variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "ingest_lambda_name" {
  type = string
}

variable "transform_lambda_name" {
  type = string
}

variable "queue_name" {
  type = string
}

variable "dlq_name" {
  type    = string
  default = null
}

variable "dlq_enabled" {
  type    = bool
  default = false
}

variable "notification_topic_arn" {
  type    = string
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  alarm_actions = var.notification_topic_arn != null && var.notification_topic_arn != "" ? [var.notification_topic_arn] : []
}

resource "aws_cloudwatch_metric_alarm" "ingest_errors" {
  count               = var.enabled ? 1 : 0
  alarm_name          = "${var.name_prefix}-ingest-errors"
  alarm_description   = "Ingest Lambda errors > 0"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = var.ingest_lambda_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "transform_errors" {
  count               = var.enabled ? 1 : 0
  alarm_name          = "${var.name_prefix}-transform-errors"
  alarm_description   = "Transform Lambda errors > 0"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions = {
    FunctionName = var.transform_lambda_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "queue_age" {
  count               = var.enabled ? 1 : 0
  alarm_name          = "${var.name_prefix}-queue-age"
  alarm_description   = "SQS oldest message age too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 300
  treat_missing_data  = "notBreaching"
  dimensions = {
    QueueName = var.queue_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  count               = var.enabled && var.dlq_enabled ? 1 : 0
  alarm_name          = "${var.name_prefix}-dlq-messages"
  alarm_description   = "DLQ has visible messages"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  dimensions = {
    QueueName = var.dlq_name
  }
  alarm_actions = local.alarm_actions
  ok_actions    = local.alarm_actions
  tags          = var.tags
}

resource "aws_cloudwatch_dashboard" "this" {
  count          = var.enabled ? 1 : 0
  dashboard_name = "${var.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        w    = 12
        h    = 6
        properties = {
          region  = var.region
          title   = "Lambda (ingest/transform) — Invocations & Errors"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.ingest_lambda_name],
            [".", "Errors", ".", var.ingest_lambda_name],
            ["AWS/Lambda", "Invocations", "FunctionName", var.transform_lambda_name],
            [".", "Errors", ".", var.transform_lambda_name],
          ]
        }
      },
      {
        type = "metric"
        x    = 12
        y    = 0
        w    = 12
        h    = 6
        properties = {
          region  = var.region
          title   = "SQS — Queue Age / Visible"
          view    = "timeSeries"
          stacked = false
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.queue_name],
            [".", "ApproximateNumberOfMessagesVisible", ".", var.queue_name],
          ]
        }
      },
      {
        type = "metric"
        x    = 0
        y    = 6
        w    = 24
        h    = 6
        properties = {
          region  = var.region
          title   = "SQS DLQ — Visible (if configured)"
          view    = "timeSeries"
          stacked = false
          metrics = var.dlq_enabled ? [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_name],
            [".", "ApproximateAgeOfOldestMessage", ".", var.dlq_name],
          ] : []
        }
      },
    ]
  })
}

output "dashboard_name" {
  value = var.enabled ? aws_cloudwatch_dashboard.this[0].dashboard_name : null
}
