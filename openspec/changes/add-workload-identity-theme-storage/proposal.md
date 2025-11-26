# Proposal: Add Azure Workload Identity for Keycloak Theme Storage

**Change ID**: `add-workload-identity-theme-storage`  
**Status**: Draft  
**Author**: GitHub Copilot  
**Date**: 2025-11-26

## Problem Statement

Currently, the Keycloak deployment uses a hardcoded Shared Access Signature (SAS) token to download theme JARs from Azure Blob Storage. This approach has several critical issues:

1. **Time-Limited Access**: The SAS token expires on 2025-12-31, requiring manual regeneration annually
2. **Security Risk**: The SAS token is hardcoded in version control, exposing it to anyone with repository access
3. **Operational Overhead**: Manual token rotation creates maintenance burden and potential downtime if forgotten
4. **No Auditability**: SAS tokens don't provide identity-based audit trails for access monitoring

Current implementation in `terraform/modules/trustorbs/keycloak/https-keycloak-server-values.yaml`:
```yaml
curl -L -f -S -o /extensions/keycloak-theme.jar "https://trustorbstfstate2025.blob.core.windows.net/keycloak-themes/keycloak-theme.jar?se=2025-12-31T23%3A59%3A59Z&sp=r&sv=2022-11-02&sr=b&sig=2%2FB%2FZXo3rNb7rh0SzN0tQVd84kiNHmBBmd7sAcyK5dc%3D"
```

## Proposed Solution

Implement Azure Workload Identity to provide identity-based authentication for Keycloak pods to access Azure Blob Storage. This follows the same pattern already successfully used for cert-manager in the project.

### Key Benefits

1. **No Token Expiration**: Identity-based access eliminates time-limited credentials
2. **Enhanced Security**: Removes hardcoded secrets from version control and configuration
3. **Zero Maintenance**: Automatic credential rotation handled by Azure/Kubernetes
4. **Better Auditability**: Azure AD identity provides clear audit trails in Azure Monitor
5. **Consistent Pattern**: Aligns with existing cert-manager workload identity implementation

### High-Level Design

1. **Azure Resources**:
   - Create user-assigned managed identity for Keycloak
   - Assign "Storage Blob Data Reader" role to the identity for the theme storage account
   - Create federated credential linking the identity to Keycloak service account

2. **Kubernetes Resources**:
   - Create service account for Keycloak with workload identity annotations
   - Configure Keycloak pod to use the service account

3. **Theme Download**:
   - Replace curl with Azure CLI or Azure SDK in init container
   - Use managed identity authentication instead of SAS token
   - Download theme JAR using identity-based access

### Alternative Approaches Considered

1. **Azure Key Vault with CSI Driver**:
   - Store SAS token in Key Vault
   - Mount as secret using CSI driver
   - **Rejected**: Still requires token rotation, adds complexity

2. **Kubernetes Secret from External Secrets Operator**:
   - Use External Secrets to sync from Key Vault
   - **Rejected**: Still relies on SAS tokens, more moving parts

3. **Bake Theme into Custom Keycloak Image**:
   - Build custom Docker image with theme included
   - **Rejected**: Reduces flexibility for theme updates, requires image registry management

## Success Criteria

- [ ] Keycloak pods successfully download theme JAR on startup without SAS token
- [ ] No hardcoded credentials in repository or Helm values
- [ ] Theme downloads work across all environments (dev, prod, customer)
- [ ] Azure audit logs show identity-based access to blob storage
- [ ] Terraform cleanly creates and manages all required Azure resources
- [ ] Existing Keycloak functionality remains unchanged
- [ ] Documentation updated with workload identity configuration

## Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Azure permissions incorrectly configured | High - Keycloak fails to start | Medium | Test thoroughly in dev, add validation checks in Terraform |
| Workload identity not available in cluster | High - Deployment fails | Low | Already enabled in AKS cluster configuration |
| Init container lacks Azure tooling | Medium - Download fails | Medium | Use azure-cli image or install tools in init container |
| Multiple customer deployments need unique identities | Medium - Permission conflicts | Low | Use per-deployment identity naming with `${local.prefix}` |

## Dependencies

- AKS cluster with workload identity enabled (✅ already configured)
- OIDC issuer enabled on AKS (✅ already configured)
- Azure Blob Storage with Keycloak themes (assumed to exist)
- Terraform Azure provider >= 4.14.0 (✅ already configured)

## Estimated Effort

- **Design & Planning**: 2 hours
- **Implementation**: 4-6 hours
  - Terraform resources: 2 hours
  - Helm values updates: 1-2 hours
  - Testing: 2 hours
- **Documentation**: 1 hour
- **Total**: ~7-9 hours

## Open Questions

1. What is the exact Azure Storage Account name and container for Keycloak themes?
2. Should we create a separate storage account in the same resource group or use an existing one?
3. Do we need to support multiple theme versions or just the latest?
4. Should the theme storage be per-deployment or shared across all deployments?

## Next Steps

1. Validate storage account details and access requirements
2. Create detailed implementation specs for affected capabilities
3. Review and approve proposal
4. Implement Terraform resources for managed identity
5. Update Keycloak Helm values with workload identity configuration
6. Test in dev environment
7. Document the new approach
