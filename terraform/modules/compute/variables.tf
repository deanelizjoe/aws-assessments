# terraform/modules/compute/variables.tf

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "unleash-assessment"
}

variable "aws_region" {
  description = "AWS region this module is being deployed into"
  type        = string
}

variable "cognito_user_pool_id" {
  description = "ID of the Cognito User Pool in us-east-1 (used by JWT authorizer)"
  type        = string
}

variable "cognito_client_id" {
  description = "Cognito User Pool Client ID (JWT audience)"
  type        = string
}

variable "author_email" {
  description = "Author email — embedded in SNS verification payloads"
  type        = string
}

variable "repo_url" {
  description = "GitHub repo URL — embedded in SNS verification payloads"
  type        = string
  default     = "https://github.com/candidate/aws-assessment"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
