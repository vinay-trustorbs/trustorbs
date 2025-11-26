# Spec Delta: Terraform Configuration

**Capability**: Terraform Configuration  
**Change ID**: `add-workload-identity-theme-storage`  
**Change Type**: Enhancement

---

## ADDED Requirements

### Requirement: Theme Storage Configuration Variables

**ID**: `terraform-config-theme-vars-001`  
**Priority**: High  
**Rationale**: Terraform modules require input variables to configure theme storage account details without hardcoding.

The TrustOrbs Terraform module SHALL define the following input variables in `terraform/modules/trustorbs/variables.tf`:

1. **`theme_storage_account_name`**:
   - Type: `string`
   - Required: `true` (no default)
   - Description: "Name of the Azure Storage Account containing Keycloak theme JARs"
   - Validation: Must match Azure storage account naming rules (3-24 chars, lowercase alphanumeric)

2. **`theme_storage_resource_group`**:
   - Type: `string`
   - Required: `false`
   - Default: `null` (uses same resource group as module when null)
   - Description: "Resource group containing the theme storage account. Defaults to module resource group if not specified."

3. **`theme_storage_container_name`**:
   - Type: `string`
   - Required: `false`
   - Default: `"keycloak-themes"`
   - Description: "Name of the blob container within the storage account containing themes"

4. **`theme_blob_name`**:
   - Type: `string`
   - Required: `false`
   - Default: `"keycloak-theme.jar"`
   - Description: "Name of the theme JAR blob file to download"

#### Scenario: Required Variable Validation

**Given** a Terraform configuration invoking the TrustOrbs module  
**When** `theme_storage_account_name` is not provided  
**Then** `terraform plan` SHALL fail with error: "The argument 'theme_storage_account_name' is required"  
**And** the error message SHALL guide the user to provide the storage account name

#### Scenario: Default Values Applied

**Given** a Terraform configuration with only `theme_storage_account_name = "trustorbsthemes"`  
**When** `terraform plan` is executed  
**Then** `theme_storage_container_name` SHALL default to `"keycloak-themes"`  
**And** `theme_blob_name` SHALL default to `"keycloak-theme.jar"`  
**And** no validation errors SHALL occur

#### Scenario: Custom Theme Configuration

**Given** a customer requiring a custom theme version  
**When** the module is invoked with:
```hcl
theme_storage_account_name = "customstorage"
theme_storage_container_name = "custom-themes"
theme_blob_name = "theme-v2.1.0.jar"
```
**Then** all variables SHALL be accepted  
**And** the init container SHALL use these custom values  
**And** the custom theme SHALL be downloaded

---

### Requirement: Storage Account Data Source

**ID**: `terraform-config-storage-datasource-001`  
**Priority**: Medium  
**Rationale**: Terraform needs to reference the existing storage account to assign RBAC roles.

The module SHALL define a data source to look up the theme storage account:

```hcl
data "azurerm_storage_account" "keycloak_themes" {
  name                = var.theme_storage_account_name
  resource_group_name = var.theme_storage_resource_group != null ? var.theme_storage_resource_group : azurerm_resource_group.rg.name
}
```

**Behavior**:
- Data source SHALL retrieve storage account metadata
- SHALL fail gracefully if storage account doesn't exist
- SHALL provide storage account ID for RBAC scope

#### Scenario: Storage Account Lookup Success

**Given** a storage account `trustorbsthemes` exists in `rg-shared`  
**When** the data source is evaluated with `theme_storage_account_name = "trustorbsthemes"` and `theme_storage_resource_group = "rg-shared"`  
**Then** the data source SHALL successfully retrieve the storage account  
**And** `data.azurerm_storage_account.keycloak_themes.id` SHALL be populated  
**And** subsequent resources can reference this ID

#### Scenario: Storage Account Not Found

**Given** a non-existent storage account name  
**When** `terraform plan` is executed  
**Then** Terraform SHALL fail with "Error: storage account not found"  
**And** the error SHALL clearly indicate the missing storage account  
**And** no resources SHALL be created

---

### Requirement: Managed Identity Outputs

**ID**: `terraform-config-identity-outputs-001`  
**Priority**: Medium  
**Rationale**: Terraform outputs enable debugging and integration with other systems.

The module SHALL export the following outputs (create or update `terraform/modules/trustorbs/outputs.tf`):

1. **`keycloak_theme_identity_client_id`**:
   - Value: `azurerm_user_assigned_identity.keycloak_theme_reader.client_id`
   - Description: "Client ID of the Keycloak theme reader managed identity"
   - Sensitive: `false`

2. **`keycloak_theme_identity_principal_id`**:
   - Value: `azurerm_user_assigned_identity.keycloak_theme_reader.principal_id`
   - Description: "Principal ID of the Keycloak theme reader managed identity"
   - Sensitive: `false`

3. **`keycloak_service_account_name`**:
   - Value: `kubernetes_service_account_v1.keycloak.metadata[0].name`
   - Description: "Name of the Kubernetes service account for Keycloak"
   - Sensitive: `false`

#### Scenario: Output Values Available After Apply

**Given** a successful `terraform apply`  
**When** `terraform output` is executed  
**Then** all three output values SHALL be displayed  
**And** the client ID SHALL match the managed identity in Azure Portal  
**And** outputs can be used in automation scripts or documentation

#### Scenario: Outputs Used in Root Module

**Given** a root module in `terraform/environments/dev/main.tf`  
**When** the TrustOrbs module is invoked  
**Then** outputs can be referenced as `module.trustorbs.keycloak_theme_identity_client_id`  
**And** these values can be passed to other modules or logged for reference

---

### Requirement: Helm Values Template Interpolation

**ID**: `terraform-config-helm-template-001`  
**Priority**: High  
**Rationale**: Terraform must inject storage configuration into Helm values dynamically.

The Terraform Helm release resource for Keycloak SHALL use `templatefile()` or `set` blocks to interpolate storage variables into Helm values:

**Method 1: Template File** (if using external values file):
```hcl
values = [
  templatefile("${path.module}/keycloak/https-keycloak-server-values.yaml", {
    storage_account_name  = var.theme_storage_account_name
    storage_container     = var.theme_storage_container_name
    theme_blob_name       = var.theme_blob_name
    identity_client_id    = azurerm_user_assigned_identity.keycloak_theme_reader.client_id
  })
]
```

**Method 2: Set Blocks** (if using inline values):
```hcl
set {
  name  = "initContainers.themeDownloader.env.AZURE_STORAGE_ACCOUNT"
  value = var.theme_storage_account_name
}
```

#### Scenario: Template Interpolation

**Given** Helm values file uses placeholders `${storage_account_name}`  
**When** Terraform renders the template with `theme_storage_account_name = "trustorbsthemes"`  
**Then** the rendered values SHALL contain `AZURE_STORAGE_ACCOUNT=trustorbsthemes`  
**And** no placeholder strings SHALL remain in the final values  
**And** Helm release SHALL apply successfully

---

### Requirement: Resource Dependencies

**ID**: `terraform-config-dependencies-001`  
**Priority**: High  
**Rationale**: Terraform must create resources in the correct order to avoid failures.

The module SHALL ensure the following dependency chain:

```
AKS Cluster (OIDC Enabled)
    ↓
Managed Identity Created
    ↓
RBAC Role Assignment (depends on storage account)
    ↓
Federated Identity Credential (depends on AKS OIDC issuer)
    ↓
Kubernetes Service Account (depends on managed identity client ID)
    ↓
Keycloak Helm Release (depends on service account)
```

**Implicit Dependencies**: Terraform resource references automatically create most dependencies.

**Explicit Dependencies**: Use `depends_on` only when implicit dependencies are insufficient.

#### Scenario: Dependency Chain Validation

**Given** a clean Terraform state (no resources exist)  
**When** `terraform apply` is executed  
**Then** resources SHALL be created in the correct order  
**And** no resource SHALL fail due to missing dependencies  
**And** the AKS cluster SHALL exist before the managed identity  
**And** the managed identity SHALL exist before RBAC assignment  
**And** RBAC assignment SHALL complete before Kubernetes service account creation

#### Scenario: Parallel Resource Creation

**Given** resources with no interdependencies  
**When** Terraform executes the plan  
**Then** independent resources SHALL be created in parallel where possible  
**And** overall apply time SHALL be optimized  
**And** no race conditions SHALL occur

---

## MODIFIED Requirements

### Requirement: Environment Configuration Files (Modified)

**ID**: `terraform-config-env-mod-001`  
**Original Behavior**: Environment configurations did not include theme storage variables  
**New Behavior**: All environment configurations must specify theme storage account

All environment configuration files SHALL be updated with the following requirements:

1. **`terraform/environments/dev/main.tf`**:
   - SHALL add `theme_storage_account_name` to module invocation
   - MAY add custom container/blob names if dev uses different themes

2. **`terraform/environments/prod/main.tf`**:
   - SHALL add `theme_storage_account_name` to module invocation
   - SHALL ensure production uses appropriate storage account

3. **`terraform/environments/customers/main.tf`**:
   - SHALL add `theme_storage_account_name` to module invocation
   - SHALL determine whether customers share storage or have isolated storage

#### Scenario: Dev Environment Update

**Given** the dev environment configuration at `terraform/environments/dev/main.tf`  
**When** the TrustOrbs module is invoked  
**Then** the invocation SHALL include:
```hcl
module "trustorbs" {
  source = "../../modules/trustorbs"
  
  # ... existing variables ...
  
  theme_storage_account_name = "trustorbsthemes"
}
```
**And** `terraform plan` SHALL succeed without missing variable errors

---

## REMOVED Requirements

None - No existing Terraform configuration requirements are removed; only additions.

---

## Dependencies

- **Terraform Version**: >= 1.4.0 (existing requirement)
- **AzureRM Provider**: >= 4.14.0 (existing requirement)
- **Kubernetes Provider**: >= 2.0.0 (existing requirement)
- **Helm Provider**: >= 2.16.0 (existing requirement)
- **Azure Storage Account**: Must exist before Terraform apply (pre-requisite)

---

## Non-Functional Requirements

### Idempotency

- Running `terraform apply` multiple times with same configuration MUST produce no changes
- Resource updates MUST be in-place where possible (no destroy-recreate)
- State file MUST accurately reflect actual infrastructure

### Validation

- Variable validation MUST provide clear error messages
- Invalid storage account names MUST be caught before API calls
- Missing required variables MUST fail fast with actionable errors

### Documentation

- All variables MUST have clear descriptions
- Complex variables SHOULD include examples in comments
- Outputs MUST indicate their intended use case

### State Management

- No sensitive values MUST be stored in plain text in state
- State file SHOULD be stored in remote backend (Azure Storage with encryption)
- State locking MUST prevent concurrent applies

---

## Migration Notes

### Backward Compatibility

This change **breaks backward compatibility** for existing deployments:

- Existing Terraform configurations will fail validation due to missing `theme_storage_account_name` variable
- Users must update their environment configurations before applying

### Migration Steps

1. **Before Migration**:
   - Note existing SAS token URL (for rollback reference)
   - Ensure theme storage account exists and contains theme JAR
   - Document current theme version

2. **During Migration**:
   - Add `theme_storage_account_name` variable to all environment configs
   - Run `terraform plan` to review changes
   - Verify managed identity and RBAC resources in plan
   - Apply changes during maintenance window (Keycloak pods will restart)

3. **After Migration**:
   - Verify Keycloak pods start successfully
   - Check init container logs for successful theme download
   - Test Keycloak theme in browser
   - Remove SAS token references from documentation

### State Considerations

- New resources will be added to state: managed identity, RBAC, federated credential, service account
- Helm release resource will be updated (in-place) to use new values
- Keycloak pods will be recreated (rolling update, no downtime)

---

## Testing Requirements

### Terraform Validation

```bash
# Validate syntax
terraform validate

# Check formatting
terraform fmt -check -recursive

# Validate without applying
terraform plan -out=plan.tfplan
```

### Variable Testing

- Test with minimal variables (only required ones)
- Test with all variables specified
- Test with invalid storage account name (expect validation error)
- Test with non-existent storage account (expect data source error)

### Integration Testing

- Apply in dev environment with real storage account
- Verify all resources created successfully
- Check Terraform state for accuracy
- Validate outputs match Azure Portal values

### Rollback Testing

- Apply new configuration
- Revert to previous configuration (with SAS token)
- Verify rollback completes without errors
- Confirm Keycloak continues to function

---

## Documentation Updates Required

### Module README

`terraform/modules/trustorbs/Readme.md`:
- Add new variables to "Inputs" section
- Add new outputs to "Outputs" section
- Update example usage with theme storage configuration
- Add "Theme Storage Setup" section explaining storage account prerequisites

### Environment README

Create or update README in `terraform/environments/`:
- Document theme storage account setup requirements
- Provide example configurations for different scenarios
- List troubleshooting steps for storage-related issues

### Architecture Documentation

Update architecture diagrams to include:
- Theme storage account
- Managed identity for theme access
- RBAC relationships
- Workload identity flow
