output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "region_1_api_base_url" {
  value = module.regional_primary.api_base_url
}

output "region_2_api_base_url" {
  value = module.regional_secondary.api_base_url
}

output "region_1_name" {
  value = var.primary_region
}

output "region_2_name" {
  value = var.secondary_region
}
