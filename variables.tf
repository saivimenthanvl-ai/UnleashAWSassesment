variable "project_name" {
  description = "Name prefix for all resources"
  type = string
  default = "unleash-assessment"
}

variable "primary_region" {
  description = "Region hosting Cognito and one copy of the regional stack"
  type = string
  default = "us-east-1"
}

variable "secondary_region" {
  description = "Second region hosting the duplicated compute stack"
  type = string
  default = "eu-west-1"
}

variable "candidate_email" {
  description = "Candidate email address used in Cognito and SNS payloads"
  type = string
}

variable "repo_url" {
  description = "Public GitHub repository URL"
  type = string
}

variable "cognito_test_password" {
  description = "Permanent password for the test Cognito user"
  type = string
  sensitive = true
}

variable "verification_topic_arn" {
  description = "Unleash live verification SNS topic ARN"
  type = string
  default = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
}
