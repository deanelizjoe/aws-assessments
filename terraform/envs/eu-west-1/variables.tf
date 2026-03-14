# terraform/envs/eu-west-1/variables.tf

variable "project_name" {
  type    = string
  default = "unleash-assessment"
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID from us-east-1 deployment"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito Client ID from us-east-1 deployment"
  type        = string
}

variable "author_email" {
  description = "Author email embedded in SNS payloads"
  type        = string
}

variable "repo_url" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/candidate/aws-assessment"
}
