# Spec Delta: Azure Identity Management

**Capability**: Azure Identity Management  
**Change ID**: `add-workload-identity-theme-storage`  
**Change Type**: Enhancement

---

## ADDED Requirements

### Requirement: Keycloak Theme Storage Access Identity

**ID**: `azure-identity-keycloak-theme-001`  
**Priority**: High  
**Rationale**: Keycloak deployments require secure, identity-based access to Azure Blob Storage for theme JAR downloads without time-limited SAS tokens.

The system SHALL create and manage a user-assigned managed identity for Keycloak theme storage access with the following specifications:

1. **Identity Naming**: `keycloak-theme-reader-${local.prefix}` where `${local.prefix}` is the environment/deployment identifier
2. **Location**: Same Azure region and resource group as the AKS cluster
3. **Lifecycle**: Created and destroyed with the Terraform module deployment
4. **Purpose Tag**: Tagged with `Purpose = "Keycloak Theme Storage Access"`

#### Scenario: Dev Environment Identity Creation

**Given** a Terraform deployment for the dev environment  
**When** `terraform apply` is executed  
**Then** a user-assigned managed identity named `keycloak-theme-reader-dev` SHALL be created  
**And** the identity SHALL be located in the `rg-dev` resource group  
**And** the identity SHALL have the purpose tag set to "Keycloak Theme Storage Access"

#### Scenario: Customer Environment Unique Identity

**Given** a customer deployment with random prefix `abc12345`  
**When** the Terraform module is applied  
**Then** a unique identity named `keycloak-theme-reader-abc12345` SHALL be created  
**And** the identity SHALL be isolated from other customer deployments  
**And** the identity SHALL exist only in the customer's resource group

---

### Requirement: Storage Account RBAC Assignment

**ID**: `azure-identity-keycloak-theme-002`  
**Priority**: High  
**Rationale**: Managed identity requires explicit RBAC permissions to read blob data from the theme storage account.

The system SHALL assign the "Storage Blob Data Reader" role to the Keycloak theme reader identity with the following specifications:

1. **Role**: `Storage Blob Data Reader` (built-in Azure role)
2. **Scope**: Theme storage account or container (configurable)
3. **Principal**: Keycloak theme reader managed identity
4. **Permissions**: Read access to blobs and containers only (no write, delete, or management operations)

#### Scenario: Storage Account Level Access

**Given** a storage account named `trustorbsthemes` exists  
**When** the Keycloak module is deployed  
**Then** the managed identity SHALL be assigned "Storage Blob Data Reader" role  
**And** the role assignment SHALL be scoped to the entire storage account  
**And** the identity SHALL be able to list containers and read blobs

#### Scenario: Container Level Access (Least Privilege)

**Given** a storage container named `keycloak-themes` exists  
**When** the role assignment scope is set to container level  
**Then** the managed identity SHALL only access the `keycloak-themes` container  
**And** the identity SHALL NOT have access to other containers in the storage account  
**And** read operations SHALL succeed for blobs in `keycloak-themes`

#### Scenario: Permission Verification

**Given** the role assignment is complete  
**When** the identity attempts to read a blob  
**Then** the operation SHALL succeed without storage account keys  
**And** Azure audit logs SHALL record the access with the managed identity name  
**And** attempts to write or delete blobs SHALL be denied

---

### Requirement: Federated Identity Credential for Workload Identity

**ID**: `azure-identity-keycloak-theme-003`  
**Priority**: High  
**Rationale**: Azure Workload Identity requires federated credentials to establish trust between AKS service accounts and Azure AD managed identities.

The system SHALL create a federated identity credential with the following specifications:

1. **Credential Name**: `keycloak-theme-${local.prefix}`
2. **Parent Identity**: Keycloak theme reader managed identity
3. **Issuer**: AKS cluster OIDC issuer URL
4. **Audience**: `["api://AzureADTokenExchange"]`
5. **Subject**: `system:serviceaccount:default:keycloak`

#### Scenario: Federated Credential Creation

**Given** an AKS cluster with OIDC issuer enabled  
**And** a user-assigned managed identity for Keycloak themes exists  
**When** the federated credential is created  
**Then** the credential SHALL bind the managed identity to the `system:serviceaccount:default:keycloak` subject  
**And** the issuer SHALL match the AKS OIDC issuer URL  
**And** the audience SHALL be `api://AzureADTokenExchange`

#### Scenario: Token Exchange Flow

**Given** a Keycloak pod with workload identity enabled  
**And** the pod uses the `keycloak` service account  
**When** the pod requests an Azure AD token  
**Then** the Kubernetes service account token SHALL be exchanged for an Azure AD token  
**And** the Azure AD token SHALL grant access as the managed identity  
**And** the token exchange SHALL complete within 5 seconds

#### Scenario: Subject Mismatch Rejection

**Given** a federated credential bound to `system:serviceaccount:default:keycloak`  
**When** a pod in a different namespace attempts to use the identity  
**Then** the token exchange SHALL fail  
**And** the error message SHALL indicate subject mismatch  
**And** no Azure AD token SHALL be issued

---

## MODIFIED Requirements

None - This is a new capability addition.

---

## REMOVED Requirements

None - Existing identity management for cert-manager remains unchanged.

---

## Dependencies

- **AKS Cluster**: Must have `oidc_issuer_enabled = true` (already configured)
- **Workload Identity**: AKS must have `workload_identity_enabled = true` (already configured)
- **Storage Account**: Theme storage account must exist before role assignment
- **Kubernetes Service Account**: Keycloak service account must be created before federated credential

---

## Non-Functional Requirements

### Performance

- Identity creation SHOULD complete within 30 seconds
- Role assignment propagation SHOULD complete within 60 seconds
- Token exchange latency SHOULD be less than 5 seconds

### Security

- Managed identity MUST use Azure AD authentication (no keys or secrets)
- Role assignments MUST follow principle of least privilege (read-only access)
- Federated credentials MUST be tightly scoped to specific service accounts

### Reliability

- Identity resources MUST be idempotent (recreatable without side effects)
- Role assignments MUST automatically retry on transient failures
- Identity deletion MUST be graceful (no orphaned resources)

### Observability

- Identity creation and deletion MUST be logged in Terraform output
- Role assignments MUST be visible in Azure Portal and CLI
- Token exchanges MUST be auditable in Azure AD sign-in logs

---

## Migration Notes

This is a new identity management capability that complements the existing cert-manager identity. Both identities SHALL coexist with distinct purposes:

- **cert-manager identity**: DNS-01 challenge and certificate management
- **keycloak-theme identity**: Blob storage read access for themes

The two identities SHALL NOT share roles or federated credentials.
