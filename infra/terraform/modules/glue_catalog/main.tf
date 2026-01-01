variable "enabled" {
  type    = bool
  default = false
}

variable "database_name" {
  type = string
}

variable "crawler_name" {
  type = string
}

variable "silver_bucket_name" {
  type = string
}

variable "silver_bucket_arn" {
  type = string
}

variable "silver_prefix" {
  type    = string
  default = "silver/"
}

variable "table_prefix" {
  type    = string
  default = ""
}

variable "iam_name_prefix" {
  type        = string
  default     = null
  description = "Optional IAM role name prefix override (helps satisfy org naming policies)."
}

variable "recrawl_behavior" {
  type    = string
  default = "CRAWL_NEW_FOLDERS_ONLY"
}

variable "job_enabled" {
  type    = bool
  default = false
}

variable "job_name" {
  type    = string
  default = null
}

variable "job_script_key" {
  type    = string
  default = "glue/scripts/compact_silver.py"
}

variable "scripts_bucket_name" {
  type        = string
  default     = null
  description = "S3 bucket for Glue job scripts; defaults to silver bucket."
}

locals {
  silver_prefix_trim = trim(var.silver_prefix, "/")
  s3_target_path     = "s3://${var.silver_bucket_name}/${local.silver_prefix_trim}/"

  iam_prefix          = var.iam_name_prefix != null && var.iam_name_prefix != "" ? var.iam_name_prefix : "glue"
  scripts_bucket_name = var.scripts_bucket_name != null && var.scripts_bucket_name != "" ? var.scripts_bucket_name : var.silver_bucket_name

  job_name = var.job_name != null && var.job_name != "" ? var.job_name : "${local.iam_prefix}-silver-compact"
}

resource "aws_glue_catalog_database" "silver" {
  count = var.enabled ? 1 : 0
  name  = var.database_name
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

data "aws_iam_policy_document" "crawler" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [var.silver_bucket_arn]
  }

  statement {
    actions   = ["s3:GetObject"]
    resources = ["${var.silver_bucket_arn}/${local.silver_prefix_trim}/*"]
  }

  statement {
    actions   = ["glue:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "crawler" {
  count              = var.enabled ? 1 : 0
  name               = "${local.iam_prefix}-glue-crawler"
  assume_role_policy = data.aws_iam_policy_document.assume_glue.json
  tags               = {}
}

resource "aws_iam_role_policy" "crawler" {
  count  = var.enabled ? 1 : 0
  name   = "${local.iam_prefix}-glue-crawler"
  role   = aws_iam_role.crawler[0].id
  policy = data.aws_iam_policy_document.crawler.json
}

resource "aws_glue_crawler" "silver" {
  count         = var.enabled ? 1 : 0
  name          = var.crawler_name
  database_name = aws_glue_catalog_database.silver[0].name
  role          = aws_iam_role.crawler[0].arn
  table_prefix  = var.table_prefix

  s3_target {
    path = local.s3_target_path
  }

  recrawl_policy {
    recrawl_behavior = var.recrawl_behavior
  }

  schema_change_policy {
    delete_behavior = "DEPRECATE_IN_DATABASE"
    update_behavior = "UPDATE_IN_DATABASE"
  }
}

resource "aws_s3_object" "job_script" {
  count        = var.enabled && var.job_enabled ? 1 : 0
  bucket       = local.scripts_bucket_name
  key          = var.job_script_key
  content_type = "text/x-python"
  source       = "${path.module}/scripts/compact_silver.py"
  etag         = filemd5("${path.module}/scripts/compact_silver.py")
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
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.silver_bucket_arn}/*"]
  }
}

resource "aws_iam_role" "job" {
  count              = var.enabled && var.job_enabled ? 1 : 0
  name               = "${local.iam_prefix}-glue-job"
  assume_role_policy = data.aws_iam_policy_document.assume_glue.json
  tags               = {}
}

resource "aws_iam_role_policy" "job" {
  count  = var.enabled && var.job_enabled ? 1 : 0
  name   = "${local.iam_prefix}-glue-job"
  role   = aws_iam_role.job[0].id
  policy = data.aws_iam_policy_document.job.json
}

resource "aws_glue_job" "compact_silver" {
  count    = var.enabled && var.job_enabled ? 1 : 0
  name     = local.job_name
  role_arn = aws_iam_role.job[0].arn

  glue_version      = "4.0"
  worker_type       = "G.1X"
  number_of_workers = 2

  command {
    name            = "glueetl"
    python_version  = "3"
    script_location = "s3://${local.scripts_bucket_name}/${var.job_script_key}"
  }

  default_arguments = {
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = "true"
    "--job-language"                     = "python"
    "--TempDir"                          = "s3://${var.silver_bucket_name}/glue/tmp/"
  }

  depends_on = [aws_s3_object.job_script]
}

output "database_name" {
  value = var.enabled ? aws_glue_catalog_database.silver[0].name : null
}

output "crawler_name" {
  value = var.enabled ? aws_glue_crawler.silver[0].name : null
}

output "crawler_role_arn" {
  value = var.enabled ? aws_iam_role.crawler[0].arn : null
}

output "job_name" {
  value = var.enabled && var.job_enabled ? aws_glue_job.compact_silver[0].name : null
}

output "job_role_arn" {
  value = var.enabled && var.job_enabled ? aws_iam_role.job[0].arn : null
}

output "job_script_s3_uri" {
  value = var.enabled && var.job_enabled ? "s3://${local.scripts_bucket_name}/${var.job_script_key}" : null
}
