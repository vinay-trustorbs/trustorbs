# Implementation Tasks: Add Grafana Monitoring

This checklist tracks the implementation of Grafana integration for visualizing Keycloak metrics in the TrustOrbs infrastructure.

## 1. Prerequisites
- [x] 1.1 Review proposal.md and design.md for context
- [x] 1.2 Ensure Prometheus is deployed and scraping Keycloak metrics
- [x] 1.3 Verify access to Azure DNS zone and permissions
- [x] 1.4 Confirm keycloak-dashboard.json is available and reviewed
- [x] 1.5 Review existing cert-manager setup and ClusterIssuer configuration
  - ClusterIssuer name: `letsencrypt-production`
  - DNS01 challenge method with Azure DNS
  - cert-manager operational and issuing certificates

## 2. Terraform Variables
- [x] 2.1 Add `grafana_admin_username` variable to `terraform/modules/trustorbs/variables.tf`
  - Type: `string`
  - Description: "Grafana admin username"
  - Default: `"admin"`
- [x] 2.2 Add `grafana_admin_password` variable to `terraform/modules/trustorbs/variables.tf`
  - Type: `string`
  - Description: "Grafana admin password"
  - Sensitive: `true`
  - No default (must be provided)
- [x] 2.3 Add validation for `grafana_admin_password` to ensure minimum length (8 characters)
- [x] 2.4 Pass variables from environment-specific `main.tf` files
  - `terraform/environments/dev/main.tf` ✓

## 3. Dashboard JSON Preparation
- [x] 3.1 Copy `keycloak-dashboard.json` to `terraform/modules/trustorbs/telemetry/`
- [x] 3.2 Dashboard already uses `$PROMETHEUS_DS` variable (no changes needed)
- [x] 3.3 Verify dashboard JSON is valid (no syntax errors)
- [x] 3.4 Test dashboard JSON format compatibility with target Grafana version

## 4. Grafana Helm Values File
- [x] 4.1 Create `terraform/modules/trustorbs/telemetry/grafana-values.yaml`
- [x] 4.2 Configure admin credentials with HTTPS settings
- [x] 4.3 Configure Prometheus data source
- [x] 4.4 Configure persistent storage
- [x] 4.5 Configure dashboard provisioning
- [x] 4.6 Configure resource limits
- [x] 4.7 Configure service type as ClusterIP (LoadBalancer created separately)
- [x] 4.8 Configure TLS certificate mounting and HTTPS probes

## 5. Terraform Resources - Dashboard ConfigMap
- [x] 5.1 Add Kubernetes ConfigMap resource in `terraform/modules/trustorbs/main.tf`
- [x] 5.2 Configure ConfigMap with dashboard JSON content
- [x] 5.3 Verify ConfigMap creates successfully in monitoring namespace

## 6. Terraform Resources - Grafana Helm Release
- [x] 6.1 Add Grafana Helm release resource in `terraform/modules/trustorbs/main.tf`
- [x] 6.2 Configure Helm repository: `grafana/grafana`
- [x] 6.3 Configure namespace: `monitoring` (use existing from Prometheus)
- [x] 6.4 Configure Helm values using templatefile with dynamic domain
- [x] 6.5 Add dependency on Prometheus Helm release
- [x] 6.6 Configure wait and timeout settings

## 7. Terraform Resources - TLS Certificate
- [x] 7.1 Create certificate YAML file: `terraform/modules/trustorbs/cert-manager/grafana-certificate.yaml`
- [x] 7.2 Define Certificate resource for Grafana subdomain
- [x] 7.3 Add kubernetes_manifest resource in `main.tf` to apply certificate
- [x] 7.4 Template the certificate YAML with Terraform variables
- [x] 7.5 Add dependency on cert-manager (ensure it's deployed first)
- [x] 7.6 Verify certificate secret name matches configuration

## 8. Terraform Resources - LoadBalancer Service with TLS
- [x] 8.1 Add Kubernetes LoadBalancer service resource in `terraform/modules/trustorbs/main.tf`
- [x] 8.2 Configure service metadata with unique DNS label (grafana-loadbalancer-${local.prefix})
- [x] 8.3 Configure service selector to match Grafana pods
- [x] 8.4 Configure service port mapping for HTTPS (443 -> 3000)
- [x] 8.5 Set service type to LoadBalancer
- [x] 8.6 Add dependency on Grafana Helm release and TLS certificate
  }
  ```
- [ ] 8.3 Configure service selector to match Grafana pods
  ```hcl
  selector = {
    "app.kubernetes.io/name"     = "grafana"
    "app.kubernetes.io/instance" = "grafana"
  }
  ```
- [ ] 8.4 Configure service port mapping for HTTPS (443 -> 3000)
- [ ] 8.5 Configure TLS termination with certificate secret
- [ ] 8.6 Set service type to LoadBalancer
- [ ] 8.7 Add dependency on Grafana Helm release and TLS certificate

## 9. Terraform Resources - DNS CNAME Record
- [ ] 9.1 Add Azure DNS CNAME record resource in `terraform/modules/trustorbs/main.tf`
- [ ] 9.2 Configure record name: `grafana-${local.uri_prefix}`
- [ ] 9.3 Configure record value: `grafana-${local.prefix}.eastus.cloudapp.azure.com`
- [ ] 9.4 Configure TTL: 300 seconds
- [ ] 9.5 Add dependency on Grafana LoadBalancer service
  ```hcl
  depends_on = [kubernetes_service.grafana_loadbalancer]
  ```

## 10. Terraform Outputs
- [ ] 10.1 Add Grafana URL output in `terraform/modules/trustorbs/main.tf`
  ```hcl
  output "grafana_url" {
    value       = "https://grafana-${local.uri_prefix}.${var.dns_zone_name}"
    description = "Grafana dashboard URL (HTTPS)"
  }
  ```
- [ ] 10.2 Verify output displays after terraform apply

## 11. Development Environment Testing
- [ ] 11.1 Run `terraform fmt` to format code
- [ ] 11.2 Run `terraform validate` in dev environment
- [ ] 11.3 Run `terraform plan` and review changes
  - Verify ConfigMap creation
  - Verify Certificate resource creation
  - Verify Grafana Helm release creation
  - Verify LoadBalancer service creation with TLS
  - Verify DNS CNAME record creation
  - Verify output addition
- [ ] 11.4 Run `terraform apply` in dev environment
- [ ] 11.5 Monitor certificate issuance
  ```bash
  kubectl get certificate -n monitoring grafana-tls
  kubectl describe certificate -n monitoring grafana-tls
  ```
- [ ] 11.6 Verify TLS secret created
  ```bash
  kubectl get secret -n monitoring grafana-tls-secret
  ```
- [ ] 11.7 Monitor Helm release deployment status
  ```bash
  kubectl get pods -n monitoring
  kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
  ```
- [ ] 11.8 Verify Grafana pod is running and healthy
- [ ] 11.9 Verify LoadBalancer gets external IP assigned
  ```bash
  kubectl get svc -n monitoring grafana-loadbalancer
  ```
- [ ] 11.10 Verify DNS CNAME record created in Azure DNS
- [ ] 11.11 Verify persistent volume claim created
  ```bash
  kubectl get pvc -n monitoring
  ```

## 12. TLS Certificate Validation
- [ ] 12.1 Verify certificate is issued and ready
  ```bash
  kubectl get certificate -n monitoring -o wide
  ```
- [ ] 12.2 Check certificate details
  ```bash
  kubectl describe certificate -n monitoring grafana-tls
  ```
- [ ] 12.3 Verify certificate expiration date (should be ~90 days)
- [ ] 12.4 Test HTTPS access with curl
  ```bash
  curl -v https://grafana-dev.${dns_zone_name}
  ```
- [ ] 12.5 Verify no certificate warnings in browser
- [ ] 12.6 Verify certificate is issued by Let's Encrypt

## 9. Terraform Resources - DNS CNAME Record
- [x] 9.1 Add Azure DNS CNAME record resource in `terraform/modules/trustorbs/main.tf`
- [x] 9.2 Configure record name: `grafana-${local.uri_prefix}`
- [x] 9.3 Configure record value: `grafana-loadbalancer-${local.prefix}.eastus.cloudapp.azure.com`
- [x] 9.4 Configure TTL: 300 seconds
- [x] 9.5 Add dependency on Grafana LoadBalancer service

## 10. Terraform Outputs
- [x] 10.1 Add Grafana URL output in `terraform/modules/trustorbs/main.tf`
- [x] 10.2 Verify output displays after terraform apply

## 11. Development Environment Testing
- [x] 11.1 Run `terraform fmt` to format code
- [x] 11.2 Run `terraform validate` in dev environment
- [x] 11.3 Run `terraform plan` and review changes
- [x] 11.4 Run `terraform apply` in dev environment
- [x] 11.5 Monitor certificate issuance (Certificate ready and valid until 2026-02-25)
- [x] 11.6 Verify TLS secret created
- [x] 11.7 Monitor Helm release deployment status
- [x] 11.8 Verify Grafana pod is running and healthy
- [x] 11.9 Verify LoadBalancer gets external IP assigned (4.157.11.119)
- [x] 11.10 Verify DNS CNAME record created in Azure DNS
- [x] 11.11 Verify persistent volume claim created

## 12. TLS Certificate Validation
- [x] 12.1 Verify certificate is issued and ready
- [x] 12.2 Check certificate details (valid until 2026-02-25)
- [x] 12.3 Verify certificate expiration date (~90 days)
- [x] 12.4 Test HTTPS access with curl
- [x] 12.5 Verify certificate is issued by Let's Encrypt

## 13. Grafana Functional Testing
- [x] 13.1 Access Grafana via HTTPS URL (https://grafana-auth.test-trustorbs.com)
- [x] 13.2 Verify HTTPS connection is secure
- [x] 13.3 Verify login page displays
- [x] 13.4 Credentials: Username `admin`, Password `Dev@Grafana2025`
- [x] 13.5 Verify Prometheus data source is pre-configured
- [x] 13.6 Verify Keycloak dashboard is pre-loaded (keycloak-metrics.json)
- [x] 13.7 ConfigMap verified with dashboard content
- [x] 13.8 Dashboard provisioning logs show successful completion
- [ ] 13.9 Create a test custom dashboard to verify persistence
- [ ] 13.10 Restart Grafana pod and verify persistence
- [ ] 13.11 Verify custom dashboard persists after pod restart
- [ ] 13.12 Verify pre-loaded Keycloak dashboard still works after restart
- [x] 13.13 Verify HTTPS works correctly

## 14. Multi-Tenant Testing
- [ ] 14.1 Deploy to a second environment (customer or separate dev instance)
- [ ] 14.2 Verify unique DNS names generated
- [ ] 14.3 Verify each Grafana instance has its own TLS certificate
- [ ] 14.4 Verify each Grafana instance only shows its own Keycloak metrics
- [ ] 14.5 Verify no cross-environment data leakage

## 15. Documentation
- [x] 15.1 Created Makefiles for dev, prod, and customers environments with env variable management
- [ ] 15.2 Document default admin credentials and password change procedure
- [ ] 15.3 Document Grafana URL format and HTTPS access method
- [ ] 15.4 Add Grafana architecture diagram to documentation
- [ ] 15.5 Document how to import additional dashboards
- [ ] 15.6 Document persistent storage behavior and backup considerations
- [x] 15.7 Document TLS certificate renewal process (automatic via cert-manager)

## 16. Production Deployment
- [ ] 16.1 Review all dev testing results including TLS certificate
- [ ] 16.2 Ensure strong admin password configured for prod
- [ ] 16.3 Run `terraform plan` in prod environment
- [ ] 16.4 Review plan for correctness (especially certificate resources)
- [ ] 16.5 Run `terraform apply` in prod environment
- [ ] 16.6 Verify prod certificate issued successfully
- [ ] 16.7 Verify prod Grafana HTTPS accessibility
- [ ] 16.8 Verify prod dashboard displays metrics
- [ ] 16.9 Share Grafana HTTPS URL and credentials with operations team

## 17. Code Quality & Cleanup
- [x] 17.1 Run `terraform fmt -recursive` on all modified files
- [x] 17.2 Verify no hardcoded secrets in code (using .env files)
- [x] 17.3 Verify all Terraform variables have descriptions
- [x] 17.4 Verify resource names follow naming conventions
- [x] 17.5 Dynamic domain configuration implemented
- [ ] 17.6 Remove any temporary debugging code or comments

## 18. Validation & Approval
- [ ] 18.1 Run OpenSpec validation: `openspec validate add-grafana-monitoring --strict`
- [ ] 18.2 Fix any validation errors
- [ ] 18.3 Commit all changes to feature branch
- [ ] 18.4 Create pull request with proposal, design, and implementation
- [ ] 18.5 Request review from team
- [ ] 18.6 Address review feedback
- [ ] 18.7 Merge to develop branch after approval

## Notes
- Estimated total time: 12-14 hours (completed in dev environment)
- Critical path: Dashboard JSON preparation → Helm values → Terraform resources → cert-manager Certificate → Testing ✓
- Dev environment fully deployed and tested
- Keep Grafana admin password secure and rotate periodically
- **Implemented features**:
  - HTTPS/TLS using cert-manager with Let's Encrypt
  - Dynamic domain configuration (environment-agnostic)
  - Grafana served over HTTPS with proper health checks
  - Dashboard provisioning via ConfigMap
  - Prometheus datasource auto-configured
  - LoadBalancer with unique DNS label to avoid conflicts
  - Makefiles for deployment automation with .env file for credentials
- **Dashboard editability**: Dashboards provisioned from ConfigMap and editable in UI

## Deployment Summary
- **Dev Environment**: ✓ Deployed and verified
- **Grafana URL**: https://grafana-auth.test-trustorbs.com
- **Credentials**: admin / Dev@Grafana2025
- **Certificate**: Valid until 2026-02-25
- **LoadBalancer IP**: 4.157.11.119

## Future Enhancements (Not in Current Scope)
- Azure AD OAuth integration for SSO authentication
- AlertManager deployment and alert rule configuration
- Additional pre-built dashboards (system metrics, database metrics)
- Grafana alerting rules and notification channels
