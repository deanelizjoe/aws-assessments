# terraform/envs/eu-west-1/main.tf
# Root configuration for eu-west-1.
# Deploys ONLY the compute module — Cognito lives in us-east-1.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "aws-assessment/eu-west-1/terraform.tfstate"
  #   region         = "us-east-1"   # state bucket stays in us-east-1
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "assessment"
    ManagedBy   = "terraform"
    Region      = "eu-west-1"
  }
}

# ── Compute only — Cognito pool is cross-region (us-east-1) ─────────────────
module "compute" {
  source = "../../modules/compute"

  project_name = var.project_name
  aws_region   = "eu-west-1"

  # These values come from the us-east-1 deployment outputs.
  # Pass them in via tfvars or environment variables:
  #   export TF_VAR_cognito_user_pool_id=$(cd ../us-east-1 && terraform output -raw cognito_user_pool_id)
  #   export TF_VAR_cognito_client_id=$(cd ../us-east-1 && terraform output -raw cognito_client_id)
  cognito_user_pool_id = var.cognito_user_pool_id
  cognito_client_id    = var.cognito_client_id

  author_email = var.author_email
  repo_url     = var.repo_url
  tags         = local.common_tags
}
