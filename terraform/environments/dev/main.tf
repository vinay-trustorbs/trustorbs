terraform {
  backend "azurerm" {}
}

module "trustorbs" {
  source = "../../modules/trustorbs"

  environment                  = "dev"
  uri_prefix                   = "auth"
  dns_zone_name                = "test-trustorbs.com"
  dns_zone_resource_group_name = "test_trustorbs"

  # Database configuration for dev environment
  database_instances    = 1
  database_storage_size = "20Gi"

  tags = {
    Environment = "development"
  }
}

output "deployment_prefix" {
  value = module.trustorbs.deployment_prefix
}

output "aks_cluster_name" {
  value = module.trustorbs.aks_cluster_name
}

output "keycloak_url" {
  value = module.trustorbs.keycloak_url
}
