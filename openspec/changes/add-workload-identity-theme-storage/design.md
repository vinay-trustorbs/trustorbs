# Design: Workload Identity for Keycloak Theme Storage

**Change ID**: `add-workload-identity-theme-storage`  
**Version**: 1.0  
**Last Updated**: 2025-11-26

## Overview

This design document details the implementation of Azure Workload Identity to replace hardcoded SAS tokens for Keycloak theme JAR downloads. The solution provides secure, identity-based access to Azure Blob Storage without time-limited credentials.

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Azure Subscription                                          │
│                                                             │
│  ┌──────────────────────┐      ┌───────────────────────┐  │
│  │ Azure AD             │      │ Storage Account       │  │
│  │                      │      │                       │  │
│  │ ┌──────────────────┐ │      │ ┌──────────────────┐ │  │
│  │ │ Managed Identity │◄├──────┤►│ Blob Container   │ │  │
│  │ │ (Keycloak Theme) │ │      │ │ keycloak-themes  │ │  │
│  │ └────────┬─────────┘ │      │ │ - theme.jar      │ │  │
│  │          │            │      │ └──────────────────┘ │  │
│  │          │ RBAC       │      └───────────────────────┘  │
│  │          │ Storage    │                                 │
│  │          │ Blob Data  │      Role: Storage Blob         │
│  │          │ Reader     │            Data Reader          │
│  │          │            │                                 │
│  └──────────┼────────────┘                                 │
│             │                                               │
│             │ Federated Credential                          │
│             │                                               │
│  ┌──────────▼──────────────────────────────────────────┐   │
│  │ AKS Cluster (OIDC Enabled)                         │   │
│  │                                                     │   │
│  │  ┌────────────────────────────────────────────┐   │   │
│  │  │ Namespace: default                         │   │   │
│  │  │                                            │   │   │
│  │  │  ┌──────────────────────────────────┐    │   │   │
│  │  │  │ ServiceAccount: keycloak         │    │   │   │
│  │  │  │ Annotations:                     │    │   │   │
│  │  │  │  - azure.workload.identity/      │    │   │   │
│  │  │  │    client-id: <identity-id>      │    │   │   │
│  │  │  │  - azure.workload.identity/      │    │   │   │
│  │  │  │    use: "true"                   │    │   │   │
│  │  │  └─────────────┬────────────────────┘    │   │   │
│  │  │                │                          │   │   │
│  │  │  ┌─────────────▼──────────────────────┐  │   │   │
│  │  │  │ Keycloak Pod                       │  │   │   │
│  │  │  │ Labels:                            │  │   │   │
│  │  │  │  - azure.workload.identity/        │  │   │   │
│  │  │  │    use: "true"                     │  │   │   │
│  │  │  │                                    │  │   │   │
│  │  │  │  ┌──────────────────────────────┐ │  │   │   │
│  │  │  │  │ Init Container:              │ │  │   │   │
│  │  │  │  │   theme-downloader           │ │  │   │   │
│  │  │  │  │                              │ │  │   │   │
│  │  │  │  │ Image: azure-cli             │ │  │   │   │
│  │  │  │  │                              │ │  │   │   │
│  │  │  │  │ 1. az login --identity       │ │  │   │   │
│  │  │  │  │ 2. az storage blob download  │ │  │   │   │
│  │  │  │  │    --auth-mode login         │ │  │   │   │
│  │  │  │  │ 3. Save to /extensions/      │ │  │   │   │
│  │  │  │  └──────────────────────────────┘ │  │   │   │
│  │  │  │                                    │  │   │   │
│  │  │  │  ┌──────────────────────────────┐ │  │   │   │
│  │  │  │  │ Keycloak Container           │ │  │   │   │
│  │  │  │  │ Uses theme from /opt/        │ │  │   │   │
│  │  │  │  │   keycloak/providers/        │ │  │   │   │
│  │  │  │  └──────────────────────────────┘ │  │   │   │
│  │  │  └────────────────────────────────────┘  │   │   │
│  │  └────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Authentication Flow

1. **Pod Startup**: Keycloak pod starts with workload identity label
2. **Token Acquisition**: Azure Workload Identity mutating webhook injects projected service account token
3. **Identity Exchange**: Init container exchanges K8s token for Azure AD token via federated credential
4. **Blob Access**: Azure CLI uses Azure AD token to authenticate to Storage Account
5. **Download**: Theme JAR downloaded using identity-based RBAC permissions
6. **Mount**: Downloaded JAR available to Keycloak main container via shared volume

## Detailed Design

### 1. Azure Resources

#### 1.1 User-Assigned Managed Identity

**Resource**: `azurerm_user_assigned_identity.keycloak_theme_reader`

```hcl
resource "azurerm_user_assigned_identity" "keycloak_theme_reader" {
  name                = "keycloak-theme-reader-${local.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  tags = merge(var.tags, {
    "Purpose" = "Keycloak Theme Storage Access"
  })
}
```

**Naming Convention**: `keycloak-theme-reader-{environment/prefix}`
- Dev: `keycloak-theme-reader-dev`
- Customer: `keycloak-theme-reader-abc12345`

#### 1.2 RBAC Role Assignment

**Resource**: `azurerm_role_assignment.keycloak_theme_storage`

```hcl
resource "azurerm_role_assignment" "keycloak_theme_storage" {
  scope                = var.theme_storage_account_id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.keycloak_theme_reader.principal_id
}
```

**Permissions**: Storage Blob Data Reader provides:
- `Microsoft.Storage/storageAccounts/blobServices/containers/read`
- `Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action`
- `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read`

**Scope Options**:
1. Storage Account level (all containers)
2. Container level (keycloak-themes only) - **Recommended**

#### 1.3 Federated Identity Credential

**Resource**: `azurerm_federated_identity_credential.keycloak_theme`

```hcl
resource "azurerm_federated_identity_credential" "keycloak_theme" {
  name                = "keycloak-theme-${local.prefix}"
  resource_group_name = azurerm_resource_group.rg.name
  parent_id           = azurerm_user_assigned_identity.keycloak_theme_reader.id
  
  audience = ["api://AzureADTokenExchange"]
  issuer   = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject  = "system:serviceaccount:default:keycloak"
}
```

**Subject Format**: `system:serviceaccount:<namespace>:<service-account-name>`

### 2. Kubernetes Resources

#### 2.1 Service Account

**Resource**: `kubernetes_service_account_v1.keycloak`

```hcl
resource "kubernetes_service_account_v1" "keycloak" {
  metadata {
    name      = "keycloak"
    namespace = "default"
    
    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.keycloak_theme_reader.client_id
      "azure.workload.identity/use"       = "true"
    }
  }
}
```

**Required Annotations**:
- `azure.workload.identity/client-id`: Links to managed identity
- `azure.workload.identity/use`: Enables workload identity for this SA

#### 2.2 Pod Configuration

**Required Pod Labels**:
```yaml
labels:
  azure.workload.identity/use: "true"
```

**Service Account Reference**:
```yaml
serviceAccountName: keycloak
```

### 3. Init Container Design

#### 3.1 Container Specification

```yaml
initContainers:
  - name: theme-downloader
    image: mcr.microsoft.com/azure-cli:2.54.0
    imagePullPolicy: IfNotPresent
    
    env:
      - name: AZURE_STORAGE_ACCOUNT
        value: "trustorbstfstate2025"
      - name: AZURE_STORAGE_CONTAINER
        value: "keycloak-themes"
      - name: THEME_BLOB_NAME
        value: "keycloak-theme.jar"
    
    command:
      - /bin/bash
    args:
      - -c
      - |
        set -e
        echo "Starting theme download with managed identity..."
        
        # Login with managed identity
        echo "Authenticating with Azure..."
        az login --identity --allow-no-subscriptions
        
        # Download theme JAR
        echo "Downloading theme: ${THEME_BLOB_NAME}"
        az storage blob download \
          --account-name "${AZURE_STORAGE_ACCOUNT}" \
          --container-name "${AZURE_STORAGE_CONTAINER}" \
          --name "${THEME_BLOB_NAME}" \
          --file "/extensions/${THEME_BLOB_NAME}" \
          --auth-mode login
        
        echo "Download complete. Verifying file..."
        ls -lh "/extensions/${THEME_BLOB_NAME}"
        
        echo "Theme download successful!"
    
    volumeMounts:
      - name: extensions
        mountPath: /extensions
```

#### 3.2 Error Handling

**Failure Scenarios**:
1. **Identity Auth Failure**: 
   - Error: "No Managed Identity found"
   - Cause: Missing workload identity webhook or incorrect annotations
   - Resolution: Verify pod labels and service account annotations

2. **Storage Access Denied**:
   - Error: "This request is not authorized"
   - Cause: Missing RBAC role assignment
   - Resolution: Check role assignment scope and identity

3. **Blob Not Found**:
   - Error: "The specified blob does not exist"
   - Cause: Incorrect blob name or container
   - Resolution: Verify environment variables and storage structure

4. **Network Issues**:
   - Error: "Connection timeout"
   - Cause: Network policy or firewall blocking storage access
   - Resolution: Check AKS network policies and storage firewall rules

### 4. Volume Sharing

**Volume Definition**:
```yaml
volumes:
  - name: extensions
    emptyDir: {}
```

**Init Container Mount**:
```yaml
volumeMounts:
  - name: extensions
    mountPath: /extensions
```

**Main Container Mount**:
```yaml
volumeMounts:
  - name: extensions
    mountPath: /opt/keycloak/providers
```

**Flow**: Init container writes to `/extensions/` → Shared volume → Keycloak reads from `/opt/keycloak/providers/`

## Storage Account Design

### Option 1: Shared Storage Account (Recommended)

**Pros**:
- Single source of truth for themes
- Simplified theme updates (one location)
- Cost-effective (one storage account)
- Easy rollback (blob versioning)

**Cons**:
- Single point of failure
- All environments share same theme versions

**Implementation**:
```hcl
# In root/shared Terraform
resource "azurerm_storage_account" "keycloak_themes" {
  name                     = "trustorbsthemes"
  resource_group_name      = "rg-shared"
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "themes" {
  name                  = "keycloak-themes"
  storage_account_name  = azurerm_storage_account.keycloak_themes.name
  container_access_type = "private"
}

# In module
data "azurerm_storage_account" "keycloak_themes" {
  name                = var.theme_storage_account_name
  resource_group_name = var.theme_storage_resource_group
}
```

### Option 2: Per-Deployment Storage

**Pros**:
- Complete isolation per environment
- Different theme versions per environment
- No cross-environment dependencies

**Cons**:
- Higher cost (multiple storage accounts)
- Theme update complexity
- Duplicated theme files

**Use Case**: Only if environments need different theme versions

## Security Considerations

### 1. Principle of Least Privilege

- **Read-Only Access**: Storage Blob Data Reader (not Contributor)
- **Scoped to Container**: RBAC only for `keycloak-themes` container
- **No Data Plane Keys**: No storage account keys exposed

### 2. Identity Isolation

- **Per-Deployment Identity**: Each environment gets unique managed identity
- **Separate Service Accounts**: No shared service accounts across namespaces
- **Federated Credential Binding**: Tightly coupled to specific K8s service account

### 3. Audit and Monitoring

**Azure Monitor Queries**:
```kusto
// Identity authentication events
AzureDiagnostics
| where ResourceType == "STORAGEACCOUNTS"
| where identity_name_s contains "keycloak-theme-reader"
| project TimeGenerated, OperationName, CallerIpAddress, identity_name_s
```

**Metrics to Monitor**:
- Blob download success rate
- Identity authentication failures
- Unauthorized access attempts

### 4. Network Security

**Storage Firewall** (Optional):
- Restrict to AKS egress IPs
- Allow Azure services on trusted list
- Private endpoint for enhanced security (future enhancement)

## Migration Strategy

### Phase 1: Preparation
1. Create storage account with theme JAR
2. Test Azure CLI download manually in pod
3. Verify RBAC permissions

### Phase 2: Parallel Implementation
1. Add managed identity and RBAC alongside existing SAS token
2. Update init container to try identity first, fallback to SAS token
3. Deploy to dev environment

### Phase 3: Validation
1. Monitor init container logs
2. Verify identity-based downloads work
3. Check Azure audit logs

### Phase 4: Cutover
1. Remove SAS token fallback
2. Deploy to all environments
3. Delete hardcoded SAS URLs

### Phase 5: Cleanup
1. Revoke old SAS tokens
2. Update documentation
3. Remove old backup configurations

## Rollback Plan

If issues arise:

1. **Immediate**: Revert Helm values to SAS token version
2. **Short-term**: Keep SAS token configuration in version control for 30 days
3. **Emergency**: Manual theme JAR injection via kubectl cp

## Performance Considerations

### Init Container Impact

**Current (SAS Token)**:
- Network overhead: ~5-10 seconds
- Single HTTP download

**New (Workload Identity)**:
- Identity login: ~2-3 seconds
- Blob download: ~5-10 seconds
- **Total**: ~7-13 seconds (2-3 seconds overhead)

**Mitigation**: Acceptable for init container (one-time cost per pod start)

### Image Size

**azure-cli Image**: ~500MB
**Alternative**: Use smaller image with just Azure SDK
- `mcr.microsoft.com/azure-cli:latest` → `mcr.microsoft.com/azure-cli:cbl-mariner2.0` (smaller)

## Testing Strategy

### Unit Tests
- Terraform validation: `terraform validate`
- Terraform plan: `terraform plan -out=plan.tfplan`

### Integration Tests

**Test Case 1: Identity Creation**
```bash
# Verify managed identity
az identity show \
  --name keycloak-theme-reader-dev \
  --resource-group rg-dev
```

**Test Case 2: RBAC Assignment**
```bash
# Verify role assignment
az role assignment list \
  --assignee <identity-principal-id> \
  --scope <storage-account-id>
```

**Test Case 3: Federated Credential**
```bash
# Verify federated credential
az identity federated-credential show \
  --name keycloak-theme-dev \
  --identity-name keycloak-theme-reader-dev \
  --resource-group rg-dev
```

**Test Case 4: Pod Identity**
```bash
# Check service account
kubectl get sa keycloak -o yaml

# Check pod labels
kubectl get pod -l app.kubernetes.io/name=keycloak -o yaml

# Check init container logs
kubectl logs -l app.kubernetes.io/name=keycloak -c theme-downloader
```

**Test Case 5: Download Success**
```bash
# Verify theme in main container
kubectl exec -it <keycloak-pod> -- ls -la /opt/keycloak/providers/
```

### End-to-End Test

1. Deploy full environment with Terraform
2. Wait for Keycloak pod to start
3. Access Keycloak admin console
4. Verify custom theme appears in theme selector
5. Check Azure storage access logs

## Monitoring and Alerting

### Key Metrics

1. **Init Container Success Rate**: Should be 100%
2. **Identity Auth Latency**: Should be < 5 seconds
3. **Blob Download Time**: Should be < 15 seconds
4. **Pod Start Time**: Watch for increases

### Alerts

**Critical Alerts**:
- Init container failures > 0 in 5 minutes
- Identity authentication failures > 3 in 10 minutes

**Warning Alerts**:
- Init container duration > 30 seconds
- Blob download failures > 1 in hour

## Documentation Updates

### 1. Architecture Docs
- Add workload identity to infrastructure diagram
- Document identity federation flow

### 2. Runbooks
- **Theme Update Process**: How to upload new theme JAR
- **Identity Troubleshooting**: Common issues and fixes
- **Rollback Procedure**: Steps to revert to SAS token

### 3. README Updates
- Prerequisites: Storage account with theme
- Configuration: New variables for storage
- Security: Identity-based access explanation

## Future Enhancements

1. **Private Endpoints**: Eliminate public internet access to storage
2. **Theme Versioning**: Support multiple theme versions with selection
3. **Cache Layer**: CDN or proxy for faster downloads
4. **Custom Image**: Build custom Keycloak image with theme baked in
5. **Helm Chart**: Package as standalone Helm chart for reusability

## References

- [Azure Workload Identity Documentation](https://azure.github.io/azure-workload-identity)
- [Azure Storage RBAC Roles](https://docs.microsoft.com/azure/storage/common/storage-auth-aad-rbac)
- [Keycloak Provider Configuration](https://www.keycloak.org/server/configuration-provider)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
