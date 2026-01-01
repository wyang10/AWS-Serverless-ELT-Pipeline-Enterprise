terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.profile
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_id" "iam_suffix" {
  byte_length = 3
}

locals {
  suffix     = var.bucket_suffix != "" ? var.bucket_suffix : random_id.suffix.hex
  name       = "${var.project}-${local.suffix}"
  tags       = var.tags
  iam_prefix = var.iam_name_prefix != null ? "${var.iam_name_prefix}-${random_id.iam_suffix.hex}" : local.name

  use_external_queue = var.existing_queue_url != null && var.existing_queue_arn != null
}

locals {
  glue_database_name = var.glue_database_name != null ? var.glue_database_name : "${replace(lower(local.name), "-", "_")}_silver"
  glue_crawler_name  = var.glue_crawler_name != null ? var.glue_crawler_name : "${local.name}-silver-crawler"
}

module "bronze_bucket" {
  source = "../../modules/s3_bucket"
  name   = "${local.name}-bronze"
  tags   = local.tags
}

module "silver_bucket" {
  source = "../../modules/s3_bucket"
  name   = "${local.name}-silver"
  tags   = local.tags
}

module "queue" {
  count  = local.use_external_queue ? 0 : 1
  source = "../../modules/sqs_queue"
  name   = "${local.name}-events"
  tags   = {}
}

locals {
  queue_url = local.use_external_queue ? var.existing_queue_url : module.queue[0].url
  queue_arn = local.use_external_queue ? var.existing_queue_arn : module.queue[0].arn
  dlq_url   = local.use_external_queue ? var.existing_dlq_url : module.queue[0].dlq_url
  dlq_arn   = local.use_external_queue ? var.existing_dlq_arn : module.queue[0].dlq_arn
}

locals {
  queue_name = split(":", local.queue_arn)[5]
  dlq_name   = local.dlq_arn != null ? split(":", local.dlq_arn)[5] : null
}

module "idempotency_table" {
  source = "../../modules/dynamodb_table"
  name   = "${local.name}-idempotency"
  tags   = local.tags
}

module "iam" {
  source                = "../../modules/iam"
  name_prefix           = local.iam_prefix
  bronze_bucket_arn     = module.bronze_bucket.arn
  silver_bucket_arn     = module.silver_bucket.arn
  queue_arn             = local.queue_arn
  idempotency_table_arn = module.idempotency_table.arn
  tags                  = {}
}

module "ingest_lambda" {
  source        = "../../modules/lambda_fn"
  function_name = "${local.name}-ingest"
  description   = "S3 ingest → SQS with object-level idempotency"
  filename      = "${path.module}/../../../../build/ingest.zip"
  handler       = "lambdas.ingest.app.handler"
  role_arn      = module.iam.ingest_role_arn
  timeout       = 30
  memory_size   = 256
  environment = {
    QUEUE_URL         = local.queue_url
    IDEMPOTENCY_TABLE = module.idempotency_table.name
    LOCK_SECONDS      = "900"
    LOG_LEVEL         = "INFO"
  }
  tags = local.tags
}

resource "aws_lambda_permission" "allow_s3_invoke_ingest" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = module.ingest_lambda.name
  principal     = "s3.amazonaws.com"
  source_arn    = module.bronze_bucket.arn
}

resource "aws_s3_bucket_notification" "bronze_to_ingest" {
  bucket = module.bronze_bucket.id
  lambda_function {
    lambda_function_arn = module.ingest_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "bronze/"
  }
  depends_on = [aws_lambda_permission.allow_s3_invoke_ingest]
}

module "transform_lambda" {
  source        = "../../modules/lambda_fn"
  function_name = "${local.name}-transform"
  description   = "SQS batch transform → S3 Parquet"
  filename      = "${path.module}/../../../../build/transform.zip"
  handler       = "lambdas.transform.app.handler"
  role_arn      = module.iam.transform_role_arn
  layers        = var.transform_layers
  timeout       = 60
  memory_size   = 512
  environment = {
    SILVER_BUCKET        = module.silver_bucket.name
    SILVER_PREFIX        = "silver"
    MAX_RECORDS_PER_FILE = "5000"
    LOG_LEVEL            = "INFO"
  }
  tags = local.tags
}

module "sqs_to_transform" {
  source                  = "../../modules/lambda_event_source_mapping"
  function_arn            = module.transform_lambda.arn
  event_source_arn        = local.queue_arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}

module "observability" {
  source                 = "../../modules/observability"
  enabled                = var.observability_enabled
  name_prefix            = local.name
  region                 = var.region
  ingest_lambda_name     = module.ingest_lambda.name
  transform_lambda_name  = module.transform_lambda.name
  queue_name             = local.queue_name
  dlq_name               = local.dlq_name
  notification_topic_arn = var.alarm_notification_topic_arn
  tags                   = local.tags
}

data "aws_iam_policy_document" "assume_lambda_workflows" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "basic_logs_workflows" {
  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }
}

data "aws_iam_policy_document" "ops_replay" {
  source_policy_documents = [data.aws_iam_policy_document.basic_logs_workflows.json]

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [module.bronze_bucket.arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${module.bronze_bucket.arn}/*"]
  }
}

resource "aws_iam_role" "ops_replay" {
  count              = var.ops_enabled ? 1 : 0
  name               = "${local.iam_prefix}-ops-replay"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_workflows.json
  tags               = {}
}

resource "aws_iam_role_policy" "ops_replay" {
  count  = var.ops_enabled ? 1 : 0
  name   = "${local.iam_prefix}-ops-replay"
  role   = aws_iam_role.ops_replay[0].id
  policy = data.aws_iam_policy_document.ops_replay.json
}

data "aws_iam_policy_document" "ops_quality" {
  source_policy_documents = [data.aws_iam_policy_document.basic_logs_workflows.json]

  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [module.silver_bucket.arn]
  }
}

resource "aws_iam_role" "ops_quality" {
  count              = var.ops_enabled ? 1 : 0
  name               = "${local.iam_prefix}-ops-quality"
  assume_role_policy = data.aws_iam_policy_document.assume_lambda_workflows.json
  tags               = {}
}

resource "aws_iam_role_policy" "ops_quality" {
  count  = var.ops_enabled ? 1 : 0
  name   = "${local.iam_prefix}-ops-quality"
  role   = aws_iam_role.ops_quality[0].id
  policy = data.aws_iam_policy_document.ops_quality.json
}

module "ops_replay_lambda" {
  count         = var.ops_enabled ? 1 : 0
  source        = "../../modules/lambda_fn"
  function_name = "${local.name}-ops-replay"
  description   = "Step Functions task: replay S3 objects by copy (triggers ingest)"
  filename      = "${path.module}/../../../../build/ops_replay.zip"
  handler       = "lambdas.workflows.replay.app.handler"
  role_arn      = aws_iam_role.ops_replay[0].arn
  timeout       = 900
  memory_size   = 512
  environment = {
    LOG_LEVEL = "INFO"
  }
  tags = local.tags
}

module "ops_quality_lambda" {
  count         = var.ops_enabled ? 1 : 0
  source        = "../../modules/lambda_fn"
  function_name = "${local.name}-ops-quality"
  description   = "Step Functions task: verify recent silver Parquet outputs exist"
  filename      = "${path.module}/../../../../build/ops_quality.zip"
  handler       = "lambdas.workflows.quality.app.handler"
  role_arn      = aws_iam_role.ops_quality[0].arn
  timeout       = 60
  memory_size   = 256
  environment = {
    LOG_LEVEL = "INFO"
  }
  tags = local.tags
}

locals {
  ops_schedule_input = {
    bronze_bucket    = module.bronze_bucket.name
    src_prefix       = var.ops_src_prefix
    dest_prefix_base = var.ops_dest_prefix_base
    window_hours     = var.ops_window_hours

    silver_bucket       = module.silver_bucket.name
    silver_prefix       = "silver"
    record_type         = var.ops_record_type
    min_parquet_objects = var.ops_min_parquet_objects

    poll_interval_seconds = var.ops_poll_interval_seconds
    max_attempts          = var.ops_max_attempts
  }
}

module "ops_workflow" {
  count               = var.ops_enabled ? 1 : 0
  source              = "../../modules/workflow_ops"
  enabled             = var.ops_enabled
  name_prefix         = local.name
  workflow_id         = var.ops_workflow_id
  iam_name_prefix     = local.iam_prefix
  region              = var.region
  replay_lambda_arn   = module.ops_replay_lambda[0].arn
  quality_lambda_arn  = module.ops_quality_lambda[0].arn
  schedule_enabled    = var.ops_schedule_enabled
  schedule_expression = var.ops_schedule_expression
  schedule_input      = local.ops_schedule_input
  tags                = {}
}

module "glue_catalog" {
  count              = var.glue_enabled ? 1 : 0
  source             = "../../modules/glue_catalog"
  enabled            = var.glue_enabled
  database_name      = local.glue_database_name
  crawler_name       = local.glue_crawler_name
  silver_bucket_name = module.silver_bucket.name
  silver_bucket_arn  = module.silver_bucket.arn
  silver_prefix      = var.glue_silver_prefix
  table_prefix       = var.glue_table_prefix
  recrawl_behavior   = var.glue_recrawl_behavior
  iam_name_prefix    = local.iam_prefix

  job_enabled    = var.glue_job_enabled
  job_name       = var.glue_job_name
  job_script_key = var.glue_job_script_key
}
