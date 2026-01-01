project                 = "serverless-elt"
region                  = "us-east-2"
iam_name_prefix         = "terraform-test"
transform_layers        = ["arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python311:24"]
observability_enabled   = false
ops_enabled             = true
ops_workflow_id         = "ops-replay-and-quality-gate"
ops_schedule_enabled    = false
ops_schedule_expression = "rate(1 day)"
glue_enabled            = true
tags = {
  app = "serverless-elt"
}
