# Project Context

## Purpose
TrustOrbs is an infrastructure-as-code project that deploys multi-tenant Keycloak identity and access management (IAM) instances on Azure Kubernetes Service (AKS). The project enables deployment of isolated Keycloak environments for different customers with automated TLS certificate management, monitoring, and DNS configuration.

## Tech Stack
- **Infrastructure**: Terraform (>= 1.4.0)
- **Cloud Platform**: Microsoft Azure (AKS, Azure DNS, Resource Groups)
- **Container Orchestration**: Kubernetes (Azure Kubernetes Service)
- **Identity Management**: Keycloak (codecentric/keycloakx Helm chart)
- **Database**: PostgreSQL (CloudNativePG operator)
- **Certificate Management**: Cert-Manager (jetstack/cert-manager v1.16.2) with Let's Encrypt
- **Monitoring**: Prometheus (prometheus-community/prometheus v27.8.0)
- **Package Management**: Helm (>= 2.16.0)
- **Additional Tools**: kubectl (>= 1.14.0), Azure CLI

## Project Conventions

### Code Style
- **Terraform**: Use HCL (HashiCorp Configuration Language) with standard formatting
- **Naming Conventions**:
  - Resources: `<type>-${local.prefix}` (e.g., `rg-dev`, `aks-customer1`)
  - Variables: snake_case (e.g., `dns_zone_name`, `dns_zone_resource_group_name`)
  - Locals: snake_case with descriptive names
- **File Organization**: 
  - Terraform modules in `terraform/modules/trustorbs/`
  - Environment-specific configurations in `terraform/environments/{dev,prod,customers}/`
  - Helm values files organized by component (cert-manager, keycloak, telemetry)

### Architecture Patterns
- **Multi-Tenant Deployment**: Supports multiple customer environments using Terraform workspaces
- **Modular Design**: Reusable Terraform module (`trustorbs`) for deploying complete stacks
- **Environment-Based Configuration**: Separate configurations for dev, prod, and customer environments
- **Random Prefix Generation**: Customer deployments use random 8-character prefixes for isolation
- **Workload Identity**: Azure Workload Identity with federated credentials for cert-manager
- **Infrastructure Provisioning Order**:
  1. Azure Resource Group & AKS Cluster
  2. User-assigned identity with DNS Zone Contributor role
  3. Cert-Manager with workload identity
  4. ClusterIssuer for Let's Encrypt
  5. Kubernetes LoadBalancer service
  6. DNS CNAME record
  7. TLS Certificate
  8. PostgreSQL database
  9. Keycloak with HTTPS
  10. Prometheus monitoring

### Testing Strategy
- Manual testing through Terraform plan/apply cycles
- Validation of resource creation through Azure Portal and kubectl commands
- Helm release status checks with `wait = true` and appropriate timeouts
- DNS resolution and TLS certificate verification

### Git Workflow
- **Main Branch**: `develop` (current working branch)
- **Remote**: GitHub (vinay-trustorbs/trustorbs)
- Terraform backend state managed remotely with backend configuration files

## Domain Context
- **Keycloak**: Open-source Identity and Access Management solution with features like SSO, user federation, and identity brokering
- **Multi-Customer Isolation**: Each customer deployment creates isolated resources with unique prefixes
- **DNS Management**: Automatic CNAME record creation pointing to Azure LoadBalancer FQDN
- **TLS/SSL**: Automated certificate provisioning via cert-manager and Let's Encrypt using DNS-01 challenge
- **Default Credentials**: Keycloak admin username: `admin`, password: `secret` (should be changed in production)
- **Service Exposure**: Keycloak exposed via Azure LoadBalancer on ports 80 (HTTP) and 443 (HTTPS)

## Important Constraints
- **Azure Region**: All resources deployed to `eastus`
- **Node Pool**: AKS uses auto-scaling node pool with 1-2 nodes of `Standard_B2s` VM size
- **Certificate Provider**: Let's Encrypt certificates with DNS-01 challenge via Azure DNS
- **DNS Zone**: Requires pre-existing Azure DNS Zone and resource group
- **Authentication**: Requires Azure Service Principal credentials for Terraform operations
- **Helm Chart Versions**: Fixed versions specified for reproducible deployments
- **Namespace**: Cert-manager in `cert-manager` namespace, Keycloak/PostgreSQL in `default` namespace, Prometheus in `monitoring` namespace

## External Dependencies
- **Azure Services**:
  - Azure DNS Zone (pre-existing, managed externally)
  - Azure Subscription with appropriate permissions
  - Azure Service Principal for automation
- **Helm Chart Repositories**:
  - `jetstack` - Cert-Manager charts
  - `bitnami` - PostgreSQL charts
  - `codecentric` - Keycloak charts
  - `prometheus-community` - Prometheus charts
- **Let's Encrypt**: ACME certificate authority for TLS certificates
- **DNS Provider**: Azure DNS for DNS-01 ACME challenge validation
