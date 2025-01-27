terraform {
  backend "azurerm" {}
}

module "trustorbs" {
  source = "../../modules/trustorbs"

  environment                  = "prod"
  uri_prefix                   = "auth"
  dns_zone_name                = "trustorbs.com"
  dns_zone_resource_group_name = "prod_trustorbs"

  tags = {
    Environment = "production"
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
