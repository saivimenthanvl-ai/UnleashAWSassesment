variable "project_name" {
  type = string
}

variable "candidate_email" {
  type = string
}

variable "cognito_test_password" {
  type = string
  sensitive = true
}
