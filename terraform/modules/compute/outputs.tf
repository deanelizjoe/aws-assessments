# terraform/modules/compute/outputs.tf

output "api_gateway_url" {
  description = "Base URL for the regional HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "dynamodb_table_name" {
  description = "Name of the regional DynamoDB table"
  value       = aws_dynamodb_table.greeting_logs.name
}

output "ecs_cluster_name" {
  description = "Name of the regional ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "greeter_lambda_arn" {
  description = "ARN of the Greeter Lambda"
  value       = aws_lambda_function.greeter.arn
}

output "dispatcher_lambda_arn" {
  description = "ARN of the Dispatcher Lambda"
  value       = aws_lambda_function.dispatcher.arn
}
