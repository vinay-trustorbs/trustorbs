# Spec Delta: Keycloak Deployment

**Capability**: Keycloak Deployment  
**Change ID**: `add-workload-identity-theme-storage`  
**Change Type**: Enhancement

---

## ADDED Requirements

### Requirement: Workload Identity Service Account

**ID**: `keycloak-deploy-workload-identity-001`  
**Priority**: High  
**Rationale**: Keycloak pods require a Kubernetes service account with workload identity annotations to authenticate with Azure for theme downloads.

The system SHALL create and configure a Kubernetes service account for Keycloak with the following specifications:

1. **Name**: `keycloak`
2. **Namespace**: `default` (same as Keycloak deployment)
3. **Annotations**:
   - `azure.workload.identity/client-id`: Set to managed identity client ID
   - `azure.workload.identity/use`: Set to `"true"`
4. **Lifecycle**: Managed by Terraform (not Helm)

#### Scenario: Service Account Creation

**Given** a Keycloak theme reader managed identity with client ID `12345678-abcd-efgh-ijkl-123456789012`  
**When** Terraform applies the Kubernetes service account resource  
**Then** a service account named `keycloak` SHALL be created in the `default` namespace  
**And** the annotation `azure.workload.identity/client-id` SHALL be set to `12345678-abcd-efgh-ijkl-123456789012`  
**And** the annotation `azure.workload.identity/use` SHALL be set to `"true"`

#### Scenario: Service Account Reference in Keycloak Pod

**Given** a Keycloak Helm release is configured  
**When** the Helm values specify `serviceAccount.create: false` and `serviceAccount.name: keycloak`  
**Then** Keycloak pods SHALL use the Terraform-managed service account  
**And** the pods SHALL NOT create a new service account  
**And** workload identity annotations SHALL be available to the pods

---

### Requirement: Workload Identity Pod Labels

**ID**: `keycloak-deploy-workload-identity-002`  
**Priority**: High  
**Rationale**: Azure Workload Identity webhook requires specific pod labels to inject identity tokens.

Keycloak pods SHALL have the following label to enable workload identity:

1. **Label**: `azure.workload.identity/use: "true"`
2. **Applied to**: All Keycloak pod templates in Helm values
3. **Effect**: Triggers mutating webhook to inject projected service account token volume

#### Scenario: Pod Label Configuration

**Given** Keycloak Helm values are configured  
**When** `podLabels` include `azure.workload.identity/use: "true"`  
**Then** deployed Keycloak pods SHALL have this label  
**And** the Azure Workload Identity webhook SHALL inject the identity token  
**And** the pod SHALL be able to exchange tokens with Azure AD

#### Scenario: Missing Label Failure

**Given** a Keycloak pod without the workload identity label  
**When** the init container attempts to authenticate with Azure  
**Then** `az login --identity` SHALL fail with "No Managed Identity found"  
**And** the pod SHALL fail to start  
**And** the error SHALL be visible in init container logs

---

### Requirement: Identity-Based Theme Download Init Container

**ID**: `keycloak-deploy-theme-download-001`  
**Priority**: High  
**Rationale**: Theme JAR files must be downloaded securely using Azure managed identity instead of SAS tokens.

The system SHALL configure a theme downloader init container with the following specifications:

1. **Container Name**: `theme-downloader`
2. **Image**: `mcr.microsoft.com/azure-cli:2.54.0` (or later)
3. **Image Pull Policy**: `IfNotPresent`
4. **Environment Variables**:
   - `AZURE_STORAGE_ACCOUNT`: Theme storage account name
   - `AZURE_STORAGE_CONTAINER`: Container name (e.g., `keycloak-themes`)
   - `THEME_BLOB_NAME`: Blob name (e.g., `keycloak-theme.jar`)
5. **Authentication**: Azure CLI managed identity login
6. **Download Method**: `az storage blob download` with `--auth-mode login`
7. **Volume Mount**: `/extensions` directory for theme output
8. **Error Handling**: Script exits on any error (`set -e`)

#### Scenario: Successful Theme Download

**Given** a Keycloak pod with workload identity configured  
**And** environment variables set to valid storage account and blob  
**When** the init container starts  
**Then** `az login --identity --allow-no-subscriptions` SHALL succeed  
**And** the theme JAR SHALL be downloaded to `/extensions/keycloak-theme.jar`  
**And** the file size SHALL match the blob size in storage  
**And** the init container SHALL exit with code 0  
**And** the main Keycloak container SHALL start

#### Scenario: Authentication Failure Handling

**Given** incorrect workload identity annotations  
**When** the init container runs `az login --identity`  
**Then** the command SHALL fail with a clear error message  
**And** the init container SHALL exit with non-zero code  
**And** the pod SHALL enter `Init:CrashLoopBackOff` state  
**And** `kubectl logs` SHALL show "No Managed Identity found"

#### Scenario: Blob Not Found Handling

**Given** valid authentication but non-existent blob name  
**When** the init container attempts to download  
**Then** `az storage blob download` SHALL fail with "BlobNotFound"  
**And** the init container SHALL exit with non-zero code  
**And** the error SHALL be logged clearly for troubleshooting

#### Scenario: Theme Verification

**Given** a successful theme download  
**When** the script runs `ls -lh /extensions/keycloak-theme.jar`  
**Then** the file size SHALL be displayed in human-readable format  
**And** the file SHALL have read permissions  
**And** a success message SHALL be logged: "Theme download successful!"

---

### Requirement: Theme Volume Sharing

**ID**: `keycloak-deploy-theme-volume-001`  
**Priority**: High  
**Rationale**: Downloaded theme JAR must be accessible to the main Keycloak container.

The system SHALL configure volume sharing between init container and main container with the following specifications:

1. **Volume Type**: `emptyDir` (ephemeral, pod-lifetime storage)
2. **Volume Name**: `extensions`
3. **Init Container Mount**: `/extensions` (write path)
4. **Main Container Mount**: `/opt/keycloak/providers` (read path, Keycloak provider directory)
5. **Access Mode**: Init container writes, main container reads

#### Scenario: Volume Mount Configuration

**Given** a Keycloak pod specification  
**When** volumes and volume mounts are configured  
**Then** an `emptyDir` volume named `extensions` SHALL exist  
**And** the `theme-downloader` init container SHALL mount it at `/extensions`  
**And** the `keycloak` main container SHALL mount it at `/opt/keycloak/providers`  
**And** the main container mount SHALL be read-only: false (Keycloak may unpack JARs)

#### Scenario: Theme Availability in Keycloak

**Given** theme JAR downloaded to `/extensions/keycloak-theme.jar` by init container  
**When** the main Keycloak container starts  
**Then** the theme SHALL be visible at `/opt/keycloak/providers/keycloak-theme.jar`  
**And** Keycloak SHALL load the theme provider on startup  
**And** the custom theme SHALL appear in the Keycloak admin console theme selector  
**And** realms SHALL be able to select and use the custom theme

---

### Requirement: Configuration Variables for Theme Storage

**ID**: `keycloak-deploy-config-001`  
**Priority**: Medium  
**Rationale**: Theme storage details must be configurable per environment without hardcoding.

The system SHALL support the following Terraform variables:

1. **`theme_storage_account_name`** (string, required): Azure Storage Account name containing themes
2. **`theme_storage_container_name`** (string, default: `"keycloak-themes"`): Blob container name
3. **`theme_blob_name`** (string, default: `"keycloak-theme.jar"`): Theme JAR blob name

These variables SHALL be interpolated into Helm values as environment variables for the init container.

#### Scenario: Variable Configuration in Dev Environment

**Given** the dev environment Terraform configuration  
**When** the module is invoked with `theme_storage_account_name = "trustorbsthemes"`  
**Then** the init container SHALL have environment variable `AZURE_STORAGE_ACCOUNT=trustorbsthemes`  
**And** default values SHALL be used for container and blob names if not specified  
**And** Terraform plan SHALL succeed without warnings

#### Scenario: Custom Theme Blob Name

**Given** a customer deployment requiring a specific theme version  
**When** the module is invoked with `theme_blob_name = "custom-theme-v2.jar"`  
**Then** the init container SHALL download `custom-theme-v2.jar` instead of the default  
**And** the theme SHALL be available to Keycloak under the specified name  
**And** multiple customers can use different theme versions

---

## MODIFIED Requirements

### Requirement: Init Container Configuration (Modified)

**ID**: `keycloak-deploy-init-container-mod-001`  
**Original Behavior**: Init container downloaded theme using hardcoded SAS token URL  
**New Behavior**: Init container uses Azure CLI with managed identity authentication

The init container configuration SHALL be updated with the following changes:
- **Image**: SHALL use `mcr.microsoft.com/azure-cli:2.54.0` instead of `curlimages/curl`
- **Command**: SHALL use `az login` + `az storage blob download` instead of `curl`
- **Authentication**: SHALL use `--auth-mode login` instead of SAS token in URL
- **Error Handling**: SHALL include `set -e` and explicit logging for better troubleshooting

#### Scenario: Migration from SAS Token to Identity

**Given** an existing Keycloak deployment using SAS token  
**When** the Helm values are updated to use workload identity  
**Then** the next pod restart SHALL use identity-based authentication  
**And** NO downtime SHALL occur (rolling update)  
**And** theme download SHALL succeed with new authentication method  
**And** Keycloak functionality SHALL remain unchanged

---

## REMOVED Requirements

### Requirement: SAS Token URL in Init Container (Removed)

**ID**: `keycloak-deploy-sas-token-001`  
**Reason for Removal**: SAS tokens are time-limited and require manual rotation; replaced by identity-based authentication

**Original Specification**: Init container curled `https://trustorbstfstate2025.blob.core.windows.net/keycloak-themes/keycloak-theme.jar?se=2025-12-31...`

**Removal Impact**:
- Hardcoded SAS token URL SHALL be completely removed from all Helm values files
- No SAS token rotation procedures needed
- Security risk of exposed tokens in version control eliminated

#### Scenario: Verification of SAS Token Removal

**Given** the updated Keycloak Helm values  
**When** searching for SAS token patterns (`?se=`, `?sig=`)  
**Then** no matches SHALL be found in any Helm values file  
**And** `git log` SHALL show the removal of SAS token URLs  
**And** no secrets SHALL be exposed in repository history going forward

---

## Dependencies

- **Azure Managed Identity**: Keycloak theme reader identity must exist before pod deployment
- **RBAC Assignment**: Identity must have Storage Blob Data Reader role assigned
- **Federated Credential**: Identity must be federated with Keycloak service account
- **Storage Account**: Theme storage account must contain the theme JAR blob
- **Workload Identity Webhook**: AKS cluster must have workload identity webhook installed

---

## Non-Functional Requirements

### Performance

- Init container startup (including theme download) SHOULD complete within 30 seconds
- Theme download size SHOULD be optimized (target: < 5 MB for JAR)
- Init container image pull SHOULD be cached after first deployment

### Security

- Init container MUST NOT store or log any credentials
- Theme download MUST use HTTPS (enforced by Azure Storage)
- Downloaded theme MUST NOT be writable by main container (except for Keycloak internal operations)

### Reliability

- Init container MUST fail fast on authentication errors (no retries that delay diagnosis)
- Theme download MUST verify file existence after download
- Missing theme MUST prevent pod from becoming Ready (init container failure)

### Observability

- Init container MUST log authentication steps clearly
- Theme download progress MUST be visible in container logs
- Errors MUST include actionable troubleshooting information

---

## Migration Notes

### Backward Compatibility

This change is **backward incompatible** with existing SAS token-based deployments:

- Existing pods with SAS token init containers will continue to work until pod restart
- On rolling update, new pods will use identity-based authentication
- No support for gradual migration (all-or-nothing switch per deployment)

### Rollback Procedure

If identity-based authentication fails, rollback can be performed by:

1. Reverting Helm values to previous version (with SAS token)
2. Redeploying Keycloak with `helm upgrade`
3. SAS token must still be valid for rollback to work

**Recommendation**: Keep SAS token configuration in version control for 30 days after migration for emergency rollback.

---

## Testing Requirements

### Unit Tests

- Terraform validation: All resources pass `terraform validate`
- Helm template rendering: Values produce valid Kubernetes YAML

### Integration Tests

- Service account creation and annotation verification
- Init container successful execution
- Theme file presence in main container volume
- Keycloak startup with theme loaded

### End-to-End Tests

- Full deployment from `terraform apply` to Keycloak accessible
- Custom theme visible in Keycloak admin console
- Realm configured with custom theme renders correctly
- Azure audit logs show identity-based storage access

### Failure Tests

- Missing workload identity annotations (expect pod failure)
- Invalid storage account name (expect download failure)
- Missing RBAC role assignment (expect auth failure)
- Non-existent blob (expect blob not found error)
