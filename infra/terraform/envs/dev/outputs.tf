output "bronze_bucket" {
  value = module.bronze_bucket.name
}

output "silver_bucket" {
  value = module.silver_bucket.name
}

output "queue_url" {
  value = local.queue_url
}

output "dlq_url" {
  value = local.dlq_url
}

output "ingest_lambda" {
  value = module.ingest_lambda.name
}

output "transform_lambda" {
  value = module.transform_lambda.name
}

output "dashboard_name" {
  value = module.observability.dashboard_name
}
