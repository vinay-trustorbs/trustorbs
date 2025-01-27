variable "environment" {
  description = "Environment name (dev, uat, prod, customer)"
  type        = string
}

variable "uri_prefix" {
  description = "Custom prefix for the URI"
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "The name of the DNS zone"
  type        = string
}

variable "dns_zone_resource_group_name" {
  description = "The name of the resource group containing the DNS zone"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}