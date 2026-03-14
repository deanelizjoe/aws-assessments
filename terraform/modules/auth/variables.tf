# terraform/modules/auth/variables.tf

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "unleash-assessment"
}

variable "test_user_email" {
  description = "Email address of the Cognito test user"
  type        = string
}

variable "test_user_temp_password" {
  description = "Temporary password for the Cognito test user (must meet pool policy)"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
