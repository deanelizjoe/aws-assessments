# terraform/envs/us-east-1/variables.tf

variable "project_name" {
  type    = string
  default = "unleash-assessment"
}

variable "test_user_email" {
  description = "Email for the Cognito test user — set via TF_VAR_test_user_email or tfvars"
  type        = string
}

variable "test_user_temp_password" {
  description = "Temporary password for the Cognito test user"
  type        = string
  sensitive   = true
}

variable "repo_url" {
  description = "GitHub repository URL"
  type        = string
  default     = "https://github.com/candidate/aws-assessment"
}
