variable "name_prefix" {
  type = string
}

variable "bronze_bucket_arn" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "queue_arn" {
  type = string
}

variable "idempotency_table_arn" {
  type = string
}

variable "eventbridge_put_events_enabled" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_iam_policy_document" "assume_lambda" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ingest" {
  name               = "${var.name_prefix}-ingest"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

resource "aws_iam_role" "transform" {
  name               = "${var.name_prefix}-transform"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda.json
  tags               = var.tags
}

data "aws_iam_policy_document" "basic_logs" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

data "aws_iam_policy_document" "ingest" {
  source_policy_documents = [data.aws_iam_policy_document.basic_logs.json]

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.bronze_bucket_arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.bronze_bucket_arn}/*"]
  }

  statement {
    actions   = ["sqs:SendMessage", "sqs:SendMessageBatch"]
    resources = [var.queue_arn]
  }

  statement {
    actions   = ["dynamodb:UpdateItem"]
    resources = [var.idempotency_table_arn]
  }
}

resource "aws_iam_role_policy" "ingest" {
  name   = "${var.name_prefix}-ingest"
  role   = aws_iam_role.ingest.id
  policy = data.aws_iam_policy_document.ingest.json
}

data "aws_iam_policy_document" "transform" {
  source_policy_documents = [data.aws_iam_policy_document.basic_logs.json]

  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.queue_arn]
  }

  statement {
    actions   = ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucketMultipartUploads"]
    resources = ["${var.silver_bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = var.eventbridge_put_events_enabled ? [1] : []
    content {
      actions   = ["events:PutEvents"]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "transform" {
  name   = "${var.name_prefix}-transform"
  role   = aws_iam_role.transform.id
  policy = data.aws_iam_policy_document.transform.json
}

output "ingest_role_arn" {
  value = aws_iam_role.ingest.arn
}

output "transform_role_arn" {
  value = aws_iam_role.transform.arn
}
