terraform {
  backend "azurerm" {}
}

variable "customer_name" {
  description = "Name of the customer"
  type        = string
}

module "trustorbs" {
  source = "../../modules/trustorbs"

  environment                  = "customer"
  dns_zone_name                = "demo-trustorbs.com"
  dns_zone_resource_group_name = "test_trustorbs"

  tags = {
    Environment = "customer"
    Customer    = var.customer_name
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