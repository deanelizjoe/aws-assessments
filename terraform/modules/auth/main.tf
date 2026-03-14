# terraform/modules/auth/main.tf
# Cognito User Pool — deployed ONCE in us-east-1.
# All regional API Gateways reference this pool's ARN for JWT validation.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ──────────────────────────────────────────────
# Cognito User Pool
# ──────────────────────────────────────────────
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-user-pool"

  # Password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # MFA — optional but recommended; OPTIONAL lets users self-enrol
  mfa_configuration = "OFF"

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Auto-verify email
  auto_verified_attributes = ["email"]

  # Schema attributes
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 254
    }
  }

  # Email configuration — uses Cognito default sender (suitable for sandbox)
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Prevent accidental deletion
  deletion_protection = "ACTIVE"

  tags = var.tags
}

# ──────────────────────────────────────────────
# User Pool Client (no client secret — SPA / CLI friendly)
# ──────────────────────────────────────────────
resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Enable USER_PASSWORD_AUTH so the test script can authenticate directly
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # Token validity
  access_token_validity  = 60   # minutes
  id_token_validity      = 60
  refresh_token_validity = 30   # days

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation       = true
}

# ──────────────────────────────────────────────
# Test user  (replace email in tfvars)
# ──────────────────────────────────────────────
resource "aws_cognito_user" "test_user" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.test_user_email

  attributes = {
    email          = var.test_user_email
    email_verified = "true"
  }

  # Temporary password — user must change on first sign-in unless suppressed
  temporary_password   = var.test_user_temp_password
  message_action       = "SUPPRESS" # don't send welcome email in sandbox
  force_alias_creation = false
}
