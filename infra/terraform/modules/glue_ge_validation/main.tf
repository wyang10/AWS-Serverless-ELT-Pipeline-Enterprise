variable "enabled" {
  type    = bool
  default = false
}

variable "job_name" {
  type = string
}

variable "silver_bucket_name" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "script_key" {
  type    = string
  default = "glue/scripts/ge_validate_silver.py"
}

variable "iam_name_prefix" {
  type        = string
  default     = null
  description = "Optional IAM role name prefix override (helps satisfy org naming policies)."
}

variable "additional_python_modules" {
  type        = string
  default     = "great-expectations==0.18.21"
  description = "Comma-separated list for Glue --additional-python-modules."
}

locals {
  iam_prefix = var.iam_name_prefix != null && var.iam_name_prefix != "" ? var.iam_name_prefix : "glue"
}

data "aws_iam_policy_document" "assume_glue" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "job" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.silver_bucket_arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${var.silver_bucket_arn}/*"]
  }
}

resource "aws_iam_role" "job" {
  count              = var.enabled ? 1 : 0
  name               = "${local.iam_prefix}-glue-ge-validate"
  assume_role_policy = data.aws_iam_policy_document.assume_glue.json
  tags               = {}
}

resource "aws_iam_role_policy" "job" {
  count  = var.enabled ? 1 : 0
  name   = "${local.iam_prefix}-glue-ge-validate"
  role   = aws_iam_role.job[0].id
  policy = data.aws_iam_policy_document.job.json
}

resource "aws_s3_object" "script" {
  count        = var.enabled ? 1 : 0
  bucket       = var.silver_bucket_name
  key          = var.script_key
  content_type = "text/x-python"
  source       = "${path.module}/scripts/ge_validate_silver.py"
  etag         = filemd5("${path.module}/scripts/ge_validate_silver.py")
}

resource "aws_glue_job" "ge_validate" {
  count    = var.enabled ? 1 : 0
  name     = var.job_name
  role_arn = aws_iam_role.job[0].arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${var.silver_bucket_name}/${var.script_key}"
  }

  default_arguments = {
    "--additional-python-modules"        = var.additional_python_modules
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--job-language"                     = "python"
    "--TempDir"                          = "s3://${var.silver_bucket_name}/glue/tmp/"
  }

  depends_on = [aws_s3_object.script]
}

output "job_name" {
  value = var.enabled ? aws_glue_job.ge_validate[0].name : null
}

output "job_role_arn" {
  value = var.enabled ? aws_iam_role.job[0].arn : null
}

output "script_s3_uri" {
  value = var.enabled ? "s3://${var.silver_bucket_name}/${var.script_key}" : null
}
