# terraform/envs/us-east-1/main.tf
# Root configuration for us-east-1.
# This region hosts BOTH the auth module (Cognito) and the compute module.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure for remote state (recommended for teams)
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "aws-assessment/us-east-1/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "assessment"
    ManagedBy   = "terraform"
    Region      = "us-east-1"
  }
}

# ── Auth (Cognito) — deployed ONLY here ────────────────────────────────────
module "auth" {
  source = "../../modules/auth"

  project_name            = var.project_name
  test_user_email         = var.test_user_email
  test_user_temp_password = var.test_user_temp_password
  tags                    = local.common_tags
}

# ── Compute ─────────────────────────────────────────────────────────────────
module "compute" {
  source = "../../modules/compute"

  project_name         = var.project_name
  aws_region           = "us-east-1"
  cognito_user_pool_id = module.auth.user_pool_id
  cognito_client_id    = module.auth.client_id
  author_email         = var.test_user_email
  repo_url             = var.repo_url
  tags                 = local.common_tags
}
