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

variable "database_instances" {
  description = "Number of PostgreSQL instances (1 for dev, 3 for production HA)"
  type        = number
  default     = 1
}

variable "database_storage_size" {
  description = "Storage size for PostgreSQL database (e.g., 20Gi, 50Gi)"
  type        = string
  default     = "20Gi"
}

variable "grafana_admin_username" {
  description = "Grafana admin username"
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana admin password (minimum 8 characters)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.grafana_admin_password) >= 8
    error_message = "Grafana admin password must be at least 8 characters long."
  }
}