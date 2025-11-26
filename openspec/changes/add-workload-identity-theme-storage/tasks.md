# Implementation Tasks

**Change ID**: `add-workload-identity-theme-storage`

## Status Legend
- ⬜ Not Started
- 🔄 In Progress
- ✅ Complete
- ⏸️ Blocked

---

## Phase 1: Azure Infrastructure Setup

### Task 1.1: Create User-Assigned Managed Identity
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Add Terraform resource to create user-assigned managed identity for Keycloak theme access.

**Acceptance Criteria**:
- [ ] `azurerm_user_assigned_identity` resource created in `terraform/modules/trustorbs/main.tf`
- [ ] Identity name follows pattern: `keycloak-theme-reader-${local.prefix}`
- [ ] Identity created in same resource group as AKS cluster
- [ ] Identity outputs exported for use in other resources

**Files to Modify**:
- `terraform/modules/trustorbs/main.tf`

---

### Task 1.2: Configure RBAC for Storage Access
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Assign "Storage Blob Data Reader" role to the managed identity for theme storage account.

**Acceptance Criteria**:
- [ ] `azurerm_role_assignment` resource created
- [ ] Role: "Storage Blob Data Reader"
- [ ] Scope: Storage account or container with Keycloak themes
- [ ] Principal ID references the managed identity created in Task 1.1

**Files to Modify**:
- `terraform/modules/trustorbs/main.tf`

**Dependencies**: Task 1.1

**Notes**: Need to determine if storage account should be:
- Created per deployment (in module)
- Shared across deployments (data source reference)

---

### Task 1.3: Create Federated Identity Credential
**Status**: ⬜ Not Started  
**Estimate**: 45 minutes  
**Owner**: TBD

**Description**: Create federated credential linking managed identity to Keycloak service account.

**Acceptance Criteria**:
- [ ] `azurerm_federated_identity_credential` resource created
- [ ] Subject references Kubernetes service account: `system:serviceaccount:default:keycloak`
- [ ] Issuer references AKS OIDC issuer URL
- [ ] Audience: `api://AzureADTokenExchange`

**Files to Modify**:
- `terraform/modules/trustorbs/main.tf`

**Dependencies**: Task 1.1, AKS cluster OIDC issuer

---

## Phase 2: Kubernetes Service Account Configuration

### Task 2.1: Create Kubernetes Service Account
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Create Kubernetes service account for Keycloak with workload identity annotations.

**Acceptance Criteria**:
- [ ] `kubernetes_service_account` resource created in Terraform
- [ ] Service account name: `keycloak`
- [ ] Namespace: `default`
- [ ] Annotation: `azure.workload.identity/client-id` = managed identity client ID
- [ ] Annotation: `azure.workload.identity/use` = `"true"`

**Files to Modify**:
- `terraform/modules/trustorbs/main.tf`

**Dependencies**: Task 1.1

---

## Phase 3: Keycloak Configuration Updates

### Task 3.1: Update Keycloak Service Account Reference
**Status**: ⬜ Not Started  
**Estimate**: 15 minutes  
**Owner**: TBD

**Description**: Configure Keycloak Helm release to use the created service account.

**Acceptance Criteria**:
- [ ] `serviceAccount.create` set to `false` in Helm values
- [ ] `serviceAccount.name` references the created service account
- [ ] Service account configuration added to all Keycloak values files

**Files to Modify**:
- `terraform/modules/trustorbs/keycloak/https-keycloak-server-values.yaml`
- `terraform/modules/trustorbs/keycloak/keycloak-server-values.yaml`

**Dependencies**: Task 2.1

---

### Task 3.2: Add Workload Identity Labels to Keycloak Pods
**Status**: ⬜ Not Started  
**Estimate**: 15 minutes  
**Owner**: TBD

**Description**: Add required workload identity labels to Keycloak pod spec.

**Acceptance Criteria**:
- [ ] Pod label: `azure.workload.identity/use: "true"` added
- [ ] Labels added to both HTTP and HTTPS values files

**Files to Modify**:
- `terraform/modules/trustorbs/keycloak/https-keycloak-server-values.yaml`
- `terraform/modules/trustorbs/keycloak/keycloak-server-values.yaml`

---

### Task 3.3: Update Theme Download Init Container
**Status**: ⬜ Not Started  
**Estimate**: 1 hour  
**Owner**: TBD

**Description**: Replace SAS token authentication with Azure CLI using managed identity.

**Acceptance Criteria**:
- [ ] Init container image changed to Azure CLI image (e.g., `mcr.microsoft.com/azure-cli:latest`)
- [ ] Download script uses `az storage blob download` with identity auth
- [ ] Hardcoded SAS token URL completely removed
- [ ] Storage account name and container parameterized via variables
- [ ] Error handling and logging improved

**Example Script**:
```bash
#!/bin/sh
echo "Logging in with managed identity..."
az login --identity --allow-no-subscriptions
echo "Downloading Keycloak theme JAR..."
az storage blob download \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --container-name "${CONTAINER_NAME}" \
  --name "keycloak-theme.jar" \
  --file "/extensions/keycloak-theme.jar" \
  --auth-mode login
```

**Files to Modify**:
- `terraform/modules/trustorbs/keycloak/https-keycloak-server-values.yaml`
- `terraform/modules/trustorbs/keycloak/keycloak-server-values.yaml`

**Dependencies**: Task 2.1, Task 3.1, Task 3.2

---

### Task 3.4: Add Environment Variables for Storage Configuration
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Add configurable environment variables for storage account details.

**Acceptance Criteria**:
- [ ] Environment variable `STORAGE_ACCOUNT_NAME` added to init container
- [ ] Environment variable `CONTAINER_NAME` added to init container
- [ ] Variables sourced from Terraform variables or locals
- [ ] Default values provided in Terraform variables

**Files to Modify**:
- `terraform/modules/trustorbs/variables.tf`
- `terraform/modules/trustorbs/main.tf` (Helm values template)
- `terraform/modules/trustorbs/keycloak/https-keycloak-server-values.yaml`

---

## Phase 4: Terraform Variables and Outputs

### Task 4.1: Add Storage Account Variables
**Status**: ⬜ Not Started  
**Estimate**: 20 minutes  
**Owner**: TBD

**Description**: Add Terraform variables for theme storage configuration.

**Acceptance Criteria**:
- [ ] Variable: `theme_storage_account_name` (string, required)
- [ ] Variable: `theme_storage_container_name` (string, default: "keycloak-themes")
- [ ] Variable: `theme_blob_name` (string, default: "keycloak-theme.jar")
- [ ] Variables documented with descriptions

**Files to Modify**:
- `terraform/modules/trustorbs/variables.tf`

---

### Task 4.2: Add Managed Identity Outputs
**Status**: ⬜ Not Started  
**Estimate**: 15 minutes  
**Owner**: TBD

**Description**: Export managed identity details for reference and debugging.

**Acceptance Criteria**:
- [ ] Output: `keycloak_identity_client_id`
- [ ] Output: `keycloak_identity_principal_id`
- [ ] Output: `keycloak_service_account_name`
- [ ] Outputs marked as sensitive where appropriate

**Files to Create/Modify**:
- Create `terraform/modules/trustorbs/outputs.tf` if it doesn't exist

---

## Phase 5: Environment Configuration

### Task 5.1: Update Dev Environment Configuration
**Status**: ⬜ Not Started  
**Estimate**: 15 minutes  
**Owner**: TBD

**Description**: Add storage account variables to dev environment.

**Acceptance Criteria**:
- [ ] `theme_storage_account_name` variable set in dev main.tf
- [ ] Storage account either created or referenced via data source
- [ ] Configuration tested with `terraform plan`

**Files to Modify**:
- `terraform/environments/dev/main.tf`

---

### Task 5.2: Update Customer Environment Configuration
**Status**: ⬜ Not Started  
**Estimate**: 15 minutes  
**Owner**: TBD

**Description**: Add storage account variables to customer environment template.

**Acceptance Criteria**:
- [ ] `theme_storage_account_name` variable set
- [ ] Determine if shared storage or per-customer storage
- [ ] Documentation added for customer deployment requirements

**Files to Modify**:
- `terraform/environments/customers/main.tf`

---

### Task 5.3: Update Production Environment Configuration
**Status**: ⬜ Not Started  
**Estimate**: 15 minutes  
**Owner**: TBD

**Description**: Add storage account variables to production environment.

**Acceptance Criteria**:
- [ ] `theme_storage_account_name` variable set
- [ ] Production-ready storage account configured
- [ ] Backup and redundancy considered

**Files to Modify**:
- `terraform/environments/prod/main.tf`

---

## Phase 6: Testing and Validation

### Task 6.1: Test in Dev Environment
**Status**: ⬜ Not Started  
**Estimate**: 1 hour  
**Owner**: TBD

**Description**: Deploy changes to dev environment and verify functionality.

**Acceptance Criteria**:
- [ ] `terraform plan` succeeds without errors
- [ ] `terraform apply` completes successfully
- [ ] Managed identity created with correct permissions
- [ ] Service account created with workload identity annotations
- [ ] Keycloak pods start successfully
- [ ] Theme JAR downloaded without errors
- [ ] Keycloak UI shows custom theme

**Testing Steps**:
1. Run `terraform plan` in dev environment
2. Review plan for correctness
3. Run `terraform apply`
4. Check managed identity in Azure Portal
5. Verify service account: `kubectl get sa keycloak -o yaml`
6. Check pod logs: `kubectl logs -l app.kubernetes.io/name=keycloak -c theme-downloader`
7. Verify theme in Keycloak admin console

---

### Task 6.2: Verify Azure Audit Logs
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Confirm identity-based access is logged in Azure Monitor.

**Acceptance Criteria**:
- [ ] Azure Activity Log shows managed identity accessing storage
- [ ] No unauthorized access attempts
- [ ] Audit trail shows correct service principal

**Testing Location**: Azure Portal > Storage Account > Monitoring > Activity Log

---

### Task 6.3: Test Failure Scenarios
**Status**: ⬜ Not Started  
**Estimate**: 45 minutes  
**Owner**: TBD

**Description**: Verify proper error handling and failure modes.

**Test Cases**:
- [ ] Missing storage account name (init container should fail with clear error)
- [ ] Missing blob file (should fail gracefully)
- [ ] Removed RBAC permissions (should fail with auth error)
- [ ] Invalid service account annotation (should fail with identity error)

---

## Phase 7: Documentation and Cleanup

### Task 7.1: Update Module README
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Document the workload identity configuration for Keycloak themes.

**Acceptance Criteria**:
- [ ] Architecture section updated with managed identity diagram
- [ ] Variables section includes new theme storage variables
- [ ] Outputs documented
- [ ] Prerequisites list workload identity requirement
- [ ] Example configuration provided

**Files to Modify**:
- `terraform/modules/trustorbs/Readme.md`

---

### Task 7.2: Update Keycloak README
**Status**: ⬜ Not Started  
**Estimate**: 20 minutes  
**Owner**: TBD

**Description**: Document theme download mechanism and identity configuration.

**Acceptance Criteria**:
- [ ] Explain workload identity setup for theme access
- [ ] Document required Azure storage account structure
- [ ] Add troubleshooting section for common issues
- [ ] Note the removal of SAS token requirement

**Files to Modify**:
- `terraform/modules/trustorbs/keycloak/readme.md`

---

### Task 7.3: Add Architecture Decision Record
**Status**: ⬜ Not Started  
**Estimate**: 30 minutes  
**Owner**: TBD

**Description**: Document the decision to use workload identity over SAS tokens.

**Acceptance Criteria**:
- [ ] ADR created explaining the decision
- [ ] Alternatives considered documented
- [ ] Consequences and trade-offs noted
- [ ] Follow project ADR template (if exists)

**Files to Create**:
- `documents/adr/003-workload-identity-theme-storage.md` (or appropriate number)

---

### Task 7.4: Remove Hardcoded SAS Token
**Status**: ⬜ Not Started  
**Estimate**: 10 minutes  
**Owner**: TBD

**Description**: Final cleanup to ensure no SAS tokens remain in repository.

**Acceptance Criteria**:
- [ ] Grep search confirms no SAS tokens: `rg "sig=.*%3D" --type yaml`
- [ ] Old URLs removed from all values files
- [ ] Git history check (optional: consider rewriting if sensitive)
- [ ] Security scan passes

**Files to Modify**:
- Any remaining files with hardcoded URLs

---

## Phase 8: Rollout

### Task 8.1: Deploy to Customer Environments
**Status**: ⬜ Not Started  
**Estimate**: 2 hours  
**Owner**: TBD

**Description**: Gradually roll out to customer environments after dev validation.

**Acceptance Criteria**:
- [ ] Communication sent to stakeholders about change
- [ ] Rollback plan prepared
- [ ] Deploy to one customer environment first
- [ ] Monitor for 24 hours
- [ ] Deploy to remaining customer environments

---

### Task 8.2: Deploy to Production
**Status**: ⬜ Not Started  
**Estimate**: 1 hour  
**Owner**: TBD

**Description**: Final deployment to production environment.

**Acceptance Criteria**:
- [ ] Change window scheduled
- [ ] Stakeholders notified
- [ ] Production deployment completed
- [ ] Post-deployment verification performed
- [ ] Monitoring confirms healthy state

---

## Summary

**Total Tasks**: 24  
**Estimated Total Effort**: ~9-11 hours  
**Critical Path**: Phase 1 → Phase 2 → Phase 3 → Phase 6

**Key Milestones**:
1. ✅ Azure infrastructure ready (Phase 1 complete)
2. ✅ Kubernetes resources configured (Phase 2 complete)
3. ✅ Keycloak updated and tested (Phase 3-6 complete)
4. ✅ Production deployment (Phase 8 complete)
