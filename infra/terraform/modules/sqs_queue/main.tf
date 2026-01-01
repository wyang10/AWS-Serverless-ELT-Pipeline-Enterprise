variable "name" {
  type = string
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 180
}

variable "message_retention_seconds" {
  type    = number
  default = 345600 # 4 days
}

variable "dlq_enabled" {
  type    = bool
  default = true
}

variable "max_receive_count" {
  type    = number
  default = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_sqs_queue" "dlq" {
  count                      = var.dlq_enabled ? 1 : 0
  name                       = "${var.name}-dlq"
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  tags                       = var.tags
}

resource "aws_sqs_queue" "this" {
  name                       = var.name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = var.dlq_enabled ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null

  tags = var.tags
}

output "url" {
  value = aws_sqs_queue.this.url
}

output "arn" {
  value = aws_sqs_queue.this.arn
}

output "dlq_url" {
  value = var.dlq_enabled ? aws_sqs_queue.dlq[0].url : null
}

output "dlq_arn" {
  value = var.dlq_enabled ? aws_sqs_queue.dlq[0].arn : null
}

