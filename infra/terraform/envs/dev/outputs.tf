output "bronze_bucket" {
  value = module.bronze_bucket.name
}

output "silver_bucket" {
  value = module.silver_bucket.name
}

output "idempotency_table_name" {
  value = module.idempotency_table.name
}

output "idempotency_table_arn" {
  value = module.idempotency_table.arn
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

output "ops_state_machine" {
  value = length(module.ops_workflow) > 0 ? module.ops_workflow[0].state_machine_name : null
}

output "ops_state_machine_arn" {
  value = length(module.ops_workflow) > 0 ? module.ops_workflow[0].state_machine_arn : null
}

output "glue_database_name" {
  value = length(module.glue_catalog) > 0 ? module.glue_catalog[0].database_name : null
}

output "glue_crawler_name" {
  value = length(module.glue_catalog) > 0 ? module.glue_catalog[0].crawler_name : null
}

output "glue_crawler_role_arn" {
  value = length(module.glue_catalog) > 0 ? module.glue_catalog[0].crawler_role_arn : null
}

output "glue_job_name" {
  value = length(module.glue_catalog) > 0 ? module.glue_catalog[0].job_name : null
}

output "glue_job_role_arn" {
  value = length(module.glue_catalog) > 0 ? module.glue_catalog[0].job_role_arn : null
}

output "glue_job_script_s3_uri" {
  value = length(module.glue_catalog) > 0 ? module.glue_catalog[0].job_script_s3_uri : null
}

output "ge_job_name" {
  value = length(module.ge_job) > 0 ? module.ge_job[0].job_name : null
}

output "ge_job_role_arn" {
  value = length(module.ge_job) > 0 ? module.ge_job[0].job_role_arn : null
}

output "ge_job_script_s3_uri" {
  value = length(module.ge_job) > 0 ? module.ge_job[0].script_s3_uri : null
}

output "ge_state_machine" {
  value = length(module.ge_workflow) > 0 ? module.ge_workflow[0].state_machine_name : null
}

output "ge_state_machine_arn" {
  value = length(module.ge_workflow) > 0 ? module.ge_workflow[0].state_machine_arn : null
}
