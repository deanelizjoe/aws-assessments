# terraform/envs/us-east-1/outputs.tf

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID — needed by eu-west-1 deployment"
  value       = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "Cognito Client ID — needed by test script"
  value       = module.auth.client_id
}

output "api_gateway_url_use1" {
  description = "API Gateway invoke URL for us-east-1"
  value       = module.compute.api_gateway_url
}

output "dynamodb_table_name" {
  value = module.compute.dynamodb_table_name
}

output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}
