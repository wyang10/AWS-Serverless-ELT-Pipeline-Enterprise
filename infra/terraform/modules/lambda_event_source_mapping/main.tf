variable "function_arn" {
  type = string
}

variable "event_source_arn" {
  type = string
}

variable "batch_size" {
  type    = number
  default = 10
}

variable "maximum_batching_window_in_seconds" {
  type    = number
  default = 0
}

variable "enabled" {
  type    = bool
  default = true
}

variable "function_response_types" {
  type    = list(string)
  default = []
}

resource "aws_lambda_event_source_mapping" "this" {
  event_source_arn                   = var.event_source_arn
  function_name                      = var.function_arn
  enabled                            = var.enabled
  batch_size                         = var.batch_size
  maximum_batching_window_in_seconds = var.maximum_batching_window_in_seconds
  function_response_types            = var.function_response_types
}

output "uuid" {
  value = aws_lambda_event_source_mapping.this.uuid
}

