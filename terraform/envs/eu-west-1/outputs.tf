# terraform/envs/eu-west-1/outputs.tf

output "api_gateway_url_euw1" {
  description = "API Gateway invoke URL for eu-west-1"
  value       = module.compute.api_gateway_url
}

output "dynamodb_table_name" {
  value = module.compute.dynamodb_table_name
}

output "ecs_cluster_name" {
  value = module.compute.ecs_cluster_name
}
