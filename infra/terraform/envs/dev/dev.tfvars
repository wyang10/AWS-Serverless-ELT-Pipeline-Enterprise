project               = "serverless-elt"
region                = "us-east-2"
iam_name_prefix       = "terraform-test"
transform_layers      = ["arn:aws:lambda:us-east-2:336392948345:layer:AWSSDKPandas-Python311:24"]
observability_enabled = false
tags = {
  app = "serverless-elt"
}
