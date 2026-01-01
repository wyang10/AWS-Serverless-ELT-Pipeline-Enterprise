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

variable "replay_lambda_arn" {
  type = string
}

variable "quality_lambda_arn" {
  type = string
}

variable "schedule_enabled" {
  type    = bool
  default = false
}

variable "schedule_expression" {
  type    = string
  default = "rate(1 day)"
}

variable "schedule_input" {
  type    = any
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
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
  name               = "${var.name_prefix}-ops-sfn"
  assume_role_policy = data.aws_iam_policy_document.assume_sfn.json
  tags               = var.tags
}

data "aws_iam_policy_document" "sfn" {
  statement {
    actions   = ["lambda:InvokeFunction"]
    resources = [var.replay_lambda_arn, var.quality_lambda_arn]
  }
}

resource "aws_iam_role_policy" "sfn" {
  count  = var.enabled ? 1 : 0
  name   = "${var.name_prefix}-ops-sfn"
  role   = aws_iam_role.sfn[0].id
  policy = data.aws_iam_policy_document.sfn.json
}

locals {
  definition = jsonencode({
    Comment = "Ops workflow: replay/backfill then verify silver outputs"
    StartAt = "Init"
    States = {
      Init = {
        Type       = "Pass"
        ResultPath = "$"
        Parameters = {
          "input.$" = "$"
          attempt   = 0
          "since.$" = "$$.Execution.StartTime"
        }
        Next = "Replay"
      }
      Replay = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.replay_lambda_arn
          Payload = {
            "execution_name.$"       = "$$.Execution.Name"
            "execution_start_time.$" = "$$.Execution.StartTime"
            "input.$"                = "$.input"
          }
        }
        ResultPath = "$.replay"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "States.TaskFailed"]
            IntervalSeconds = 2
            BackoffRate     = 2.0
            MaxAttempts     = 3
          },
        ]
        Next = "WaitBeforeQuality"
      }
      WaitBeforeQuality = {
        Type        = "Wait"
        SecondsPath = "$.input.poll_interval_seconds"
        Next        = "QualityCheck"
      }
      QualityCheck = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = var.quality_lambda_arn
          Payload = {
            "execution_start_time.$" = "$$.Execution.StartTime"
            "since.$"                = "$.since"
            "input.$"                = "$.input"
          }
        }
        ResultPath = "$.quality"
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "States.TaskFailed"]
            IntervalSeconds = 2
            BackoffRate     = 2.0
            MaxAttempts     = 2
          },
        ]
        Next = "CheckQuality"
      }
      CheckQuality = {
        Type = "Choice"
        Choices = [
          {
            Variable      = "$.quality.Payload.ok"
            BooleanEquals = true
            Next          = "Success"
          },
          {
            Variable                     = "$.attempt"
            NumericGreaterThanEqualsPath = "$.input.max_attempts"
            Next                         = "Failed"
          },
        ]
        Default = "IncAttempt"
      }
      IncAttempt = {
        Type       = "Pass"
        ResultPath = "$"
        Parameters = {
          "input.$"   = "$.input"
          "attempt.$" = "States.MathAdd($.attempt, 1)"
          "since.$"   = "$.since"
          "replay.$"  = "$.replay"
          "quality.$" = "$.quality"
        }
        Next = "WaitBeforeQuality"
      }
      Success = { Type = "Succeed" }
      Failed  = { Type = "Fail", Cause = "Quality check did not pass in time" }
    }
  })
}

resource "aws_sfn_state_machine" "ops" {
  count      = var.enabled ? 1 : 0
  name       = "${var.name_prefix}-ops"
  role_arn   = aws_iam_role.sfn[0].arn
  definition = local.definition
  tags       = var.tags
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
  count              = var.enabled && var.schedule_enabled ? 1 : 0
  name               = "${var.name_prefix}-ops-events"
  assume_role_policy = data.aws_iam_policy_document.assume_events.json
  tags               = var.tags
}

data "aws_iam_policy_document" "events" {
  statement {
    actions   = ["states:StartExecution"]
    resources = [aws_sfn_state_machine.ops[0].arn]
  }
}

resource "aws_iam_role_policy" "events" {
  count  = var.enabled && var.schedule_enabled ? 1 : 0
  name   = "${var.name_prefix}-ops-events"
  role   = aws_iam_role.events[0].id
  policy = data.aws_iam_policy_document.events.json
}

resource "aws_cloudwatch_event_rule" "schedule" {
  count               = var.enabled && var.schedule_enabled ? 1 : 0
  name                = "${var.name_prefix}-ops-schedule"
  schedule_expression = var.schedule_expression
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "schedule" {
  count    = var.enabled && var.schedule_enabled ? 1 : 0
  rule     = aws_cloudwatch_event_rule.schedule[0].name
  arn      = aws_sfn_state_machine.ops[0].arn
  role_arn = aws_iam_role.events[0].arn
  input    = jsonencode(var.schedule_input)
}

output "state_machine_arn" {
  value = var.enabled ? aws_sfn_state_machine.ops[0].arn : null
}

output "state_machine_name" {
  value = var.enabled ? aws_sfn_state_machine.ops[0].name : null
}
