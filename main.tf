terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source = "hashicorp/archive"
      version = "~> 2.5"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  alias = "use1"
  region = var.primary_region
}

provider "aws" {
  alias = "euw1"
  region = var.secondary_region
}

module "cognito" {
  source = "./modules/cognito"

  providers = {
    aws = aws.use1
  }

  project_name = var.project_name
  candidate_email = var.candidate_email
  cognito_test_password  = var.cognito_test_password
}

module "regional_primary" {
  source = "./modules/regional_stack"

  providers = {
    aws = aws.use1
  }

  project_name = var.project_name
  aws_region = var.primary_region
  candidate_email = var.candidate_email
  repo_url = var.repo_url
  verification_topic_arn = var.verification_topic_arn

  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id = module.cognito.user_pool_client_id
  cognito_issuer_url = module.cognito.user_pool_issuer_url
}

module "regional_secondary" {
  source = "./modules/regional_stack"

  providers = {
    aws = aws.euw1
  }

  project_name = var.project_name
  aws_region  = var.secondary_region
  candidate_email = var.candidate_email
  repo_url = var.repo_url
  verification_topic_arn = var.verification_topic_arn

  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id = module.cognito.user_pool_client_id
  cognito_issuer_url = module.cognito.user_pool_issuer_url
}
