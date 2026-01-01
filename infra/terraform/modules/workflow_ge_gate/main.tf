variable "enabled" {
  type    = bool
  default = false
}

variable "name_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "silver_bucket_arn" {
  type        = string
  description = "ARN of the silver bucket (used for optional quarantine marker writes)."
}

variable "iam_name_prefix" {
  type        = string
  default     = null
  description = "Optional IAM role name prefix override (helps satisfy org naming policies)."
}

variable "workflow_id" {
  type    = string
  default = "ge-quality-gate"
}

variable "glue_job_name" {
  type = string
}

variable "notification_topic_arn" {
  type        = string
  default     = null
  description = "Optional SNS topic ARN to publish when the quality gate fails."
}

variable "quarantine_enabled" {
  type        = bool
  default     = false
  description = "If true, write a marker JSON under quarantine_prefix on gate failure."
}

variable "quarantine_prefix" {
  type        = string
  default     = "silver/_quarantine/ge"
  description = "S3 prefix (within the same silver_bucket) for failure markers."
}

variable "eventbridge_enabled" {
  type    = bool
  default = false
}

variable "eventbridge_event_source" {
  type    = string
  default = "serverless-elt.transform"
}

variable "eventbridge_detail_type" {
  type    = string
  default = "silver_partition_ready"
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  iam_prefix            = var.iam_name_prefix != null && var.iam_name_prefix != "" ? var.iam_name_prefix : var.name_prefix
  notifications_enabled = var.notification_topic_arn != null && var.notification_topic_arn != ""
  quarantine_prefix     = trim(var.quarantine_prefix, "/")
  failure_first_state = (
    var.quarantine_enabled ? "QuarantineMarker" :
    local.notifications_enabled ? "NotifyFailure" :
    "Failed"
  )
}

data "aws_iam_policy_document" "assume_sfn" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  count              = var.enabled ? 1 : 0
  name               = "${local.iam_prefix}-${var.workflow_id}-sfn"
  assume_role_policy = data.aws_iam_policy_document.assume_sfn.json
  tags               = {}
}

data "aws_iam_policy_document" "sfn" {
  statement {
    actions = [
      "glue:StartJobRun",
      "glue:GetJobRun",
      "glue:GetJobRuns",
      "glue:BatchStopJobRun",
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = var.quarantine_enabled ? [1] : []
    content {
      actions   = ["s3:PutObject"]
      resources = ["${var.silver_bucket_arn}/${local.quarantine_prefix}/*"]
    }
  }

  dynamic "statement" {
    for_each = local.notifications_enabled ? [1] : []
    content {
      actions   = ["sns:Publish"]
      resources = [var.notification_topic_arn]
    }
  }
}

resource "aws_iam_role_policy" "sfn" {
  count  = var.enabled ? 1 : 0
  name   = "${local.iam_prefix}-${var.workflow_id}-sfn"
  role   = aws_iam_role.sfn[0].id
  policy = data.aws_iam_policy_document.sfn.json
}

locals {
  states_base = {
    ValidateWithGlueJob = {
      Type       = "Task"
      Resource   = "arn:aws:states:::glue:startJobRun.sync"
      ResultPath = "$.glue"
      Parameters = {
        JobName = var.glue_job_name
        Arguments = {
          "--SILVER_BUCKET.$" = "$.silver_bucket"
          "--SILVER_PREFIX.$" = "$.silver_prefix"
          "--RECORD_TYPE.$"   = "$.record_type"
          "--DT.$"            = "$.dt"
          "--RESULT_PREFIX.$" = "$.result_prefix"
        }
      }
      Retry = [
        {
          ErrorEquals     = ["States.TaskFailed"]
          IntervalSeconds = 10
          BackoffRate     = 2.0
          MaxAttempts     = 2
        },
      ]
      Catch = [
        {
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error"
          Next        = local.failure_first_state
        },
      ]
      Next = "Success"
    }
    Success = { Type = "Succeed" }
    Failed  = { Type = "Fail", Cause = "GE validation failed" }
  }

  state_quarantine = var.quarantine_enabled ? {
    QuarantineMarker = {
      Type     = "Task"
      Resource = "arn:aws:states:::aws-sdk:s3:putObject"
      Parameters = {
        "Bucket.$"  = "$.silver_bucket"
        "Key.$"     = "States.Format('${local.quarantine_prefix}/{}/dt={}/execution_{}.json', $.record_type, $.dt, $$.Execution.Name)"
        "Body.$"    = "States.JsonToString($)"
        ContentType = "application/json"
      }
      Catch = [
        {
          ErrorEquals = ["States.ALL"]
          Next        = local.notifications_enabled ? "NotifyFailure" : "Failed"
        },
      ]
      Next = local.notifications_enabled ? "NotifyFailure" : "Failed"
    }
  } : {}

  state_notify = local.notifications_enabled ? {
    NotifyFailure = {
      Type     = "Task"
      Resource = "arn:aws:states:::sns:publish"
      Parameters = {
        TopicArn    = var.notification_topic_arn
        Subject     = "GE quality gate failed"
        "Message.$" = "States.JsonToString($)"
      }
      Catch = [
        {
          ErrorEquals = ["States.ALL"]
          Next        = "Failed"
        },
      ]
      Next = "Failed"
    }
  } : {}

  states = merge(local.states_base, local.state_quarantine, local.state_notify)

  definition = jsonencode({
    Comment = "Great Expectations quality gate (Glue Job) for Silver partitions"
    StartAt = "ValidateWithGlueJob"
    States  = local.states
  })
}

resource "aws_sfn_state_machine" "ge_gate" {
  count      = var.enabled ? 1 : 0
  name       = "${var.name_prefix}-${var.workflow_id}"
  role_arn   = aws_iam_role.sfn[0].arn
  definition = local.definition
  tags       = {}
}

data "aws_iam_policy_document" "assume_events" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events" {
  count              = var.enabled && var.eventbridge_enabled ? 1 : 0
  name               = "${local.iam_prefix}-${var.workflow_id}-events"
  assume_role_policy = data.aws_iam_policy_document.assume_events.json
  tags               = {}
}

data "aws_iam_policy_document" "events" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.ge_gate[0].arn]
  }
}

resource "aws_iam_role_policy" "events" {
  count  = var.enabled && var.eventbridge_enabled ? 1 : 0
  name   = "${local.iam_prefix}-${var.workflow_id}-events"
  role   = aws_iam_role.events[0].id
  policy = data.aws_iam_policy_document.events.json
}

resource "aws_cloudwatch_event_rule" "trigger" {
  count = var.enabled && var.eventbridge_enabled ? 1 : 0
  name  = "${var.name_prefix}-${var.workflow_id}-trigger"
  event_pattern = jsonencode({
    source        = [var.eventbridge_event_source]
    "detail-type" = [var.eventbridge_detail_type]
  })
}

resource "aws_cloudwatch_event_target" "trigger" {
  count    = var.enabled && var.eventbridge_enabled ? 1 : 0
  rule     = aws_cloudwatch_event_rule.trigger[0].name
  arn      = aws_sfn_state_machine.ge_gate[0].arn
  role_arn = aws_iam_role.events[0].arn
  input_transformer {
    input_paths = {
      silver_bucket = "$.detail.silver_bucket"
      silver_prefix = "$.detail.silver_prefix"
      record_type   = "$.detail.record_type"
      dt            = "$.detail.dt"
    }
    input_template = "{\"silver_bucket\":<silver_bucket>,\"silver_prefix\":<silver_prefix>,\"record_type\":<record_type>,\"dt\":<dt>,\"result_prefix\":\"ge/results\"}"
  }
}

output "state_machine_arn" {
  value = var.enabled ? aws_sfn_state_machine.ge_gate[0].arn : null
}

output "state_machine_name" {
  value = var.enabled ? aws_sfn_state_machine.ge_gate[0].name : null
}
