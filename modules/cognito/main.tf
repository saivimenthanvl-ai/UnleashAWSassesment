resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-pool"

  auto_verified_attributes = ["email"]

  username_attributes = ["email"]

  password_policy {
    minimum_length = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }
}

resource "aws_cognito_user_pool_client" "this" {
  name         = "${var.project_name}-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret = false
  prevent_user_existence_errors = "ENABLED"
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  supported_identity_providers = ["COGNITO"]
  access_token_validity = 60
  id_token_validity = 60
  refresh_token_validity = 30
  auth_session_validity = 3
  enable_token_revocation = true
  enable_propagate_additional_user_context_data = false

  token_validity_units {
    access_token  = "minutes"
    id_token = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user" "candidate" {
  user_pool_id = aws_cognito_user_pool.this.id
  username     = var.candidate_email

  attributes = {
    email = var.candidate_email
    email_verified = "true"
  }

  desired_delivery_mediums = []
  force_alias_creation     = false
  message_action           = "SUPPRESS"
}

resource "null_resource" "set_permanent_password" {
  triggers = {
    user_pool_id = aws_cognito_user_pool.this.id
    username     = aws_cognito_user.candidate.username
    password_sha = sha256(var.cognito_test_password)
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws cognito-idp admin-set-user-password \
        --region ${data.aws_region.current.name} \
        --user-pool-id ${aws_cognito_user_pool.this.id} \
        --username ${aws_cognito_user.candidate.username} \
        --password '${var.cognito_test_password}' \
        --permanent
    EOT
  }

  depends_on = [aws_cognito_user.candidate]
}

data "aws_region" "current" {}
