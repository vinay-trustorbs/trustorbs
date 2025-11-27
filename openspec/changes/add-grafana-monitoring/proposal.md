# Proposal: Add Grafana for Keycloak Metrics Visualization

**Change ID**: `add-grafana-monitoring`  
**Status**: Draft  
**Author**: GitHub Copilot  
**Date**: 2025-11-27

## Problem Statement

Currently, the TrustOrbs infrastructure deploys Prometheus to collect metrics from Keycloak instances, but there is no user-friendly visualization layer for monitoring and observability. This creates several challenges:

1. **Limited Observability**: Without a dashboard, operators cannot easily visualize Keycloak's health, performance, and usage patterns
2. **Manual Metric Inspection**: Prometheus queries must be written manually through port-forwarding to the Prometheus service
3. **No Pre-built Dashboards**: The team has created a comprehensive Keycloak dashboard (keycloak-dashboard.json) that cannot be deployed
4. **Poor Accessibility**: Prometheus is only exposed internally via ClusterIP, requiring kubectl port-forwarding for access
5. **No Real-time Monitoring**: Operations teams cannot quickly identify issues or verify Keycloak status without technical Kubernetes knowledge

Current setup:
- Prometheus deployed in `monitoring` namespace with ClusterIP service
- Metrics scraped from Keycloak on port 9000 (management port)
- No visualization layer
- Access requires: `kubectl port-forward -n monitoring svc/prometheus-server 9090:80`

## Proposed Solution

Deploy Grafana as part of the monitoring stack with external accessibility via Azure LoadBalancer, pre-configured with the Keycloak metrics dashboard, and Prometheus as a data source.

### Key Benefits

1. **User-Friendly Visualization**: Rich, interactive dashboards showing Keycloak metrics, JVM stats, database connections, and system health
2. **External Accessibility**: Grafana exposed via LoadBalancer for easy access without Kubernetes knowledge
3. **Pre-configured Dashboards**: Deploy the existing keycloak-dashboard.json automatically during setup
4. **Real-time Monitoring**: Live metric visualization for operations and support teams
5. **Alerting Capability**: Future support for Grafana-based alerts and notifications
6. **Multi-tenant Support**: Separate Grafana instances per customer deployment with unique DNS endpoints

### High-Level Design

1. **Grafana Deployment**:
   - Deploy Grafana using official Helm chart (grafana/grafana)
   - Configure persistent storage for dashboard and configuration persistence
   - Set admin credentials via Kubernetes secrets

2. **External Exposure**:
   - Create Kubernetes LoadBalancer service for Grafana
   - Generate DNS CNAME record: `grafana-${local.prefix}.${dns_zone_name}`
   - Configure Azure DNS label for predictable LoadBalancer FQDN

3. **Prometheus Integration**:
   - Auto-configure Prometheus as default data source
   - Use internal Kubernetes DNS for Prometheus connectivity
   - Set `prometheus-server.monitoring.svc.cluster.local` as data source URL

4. **Dashboard Provisioning**:
   - Create ConfigMap with keycloak-dashboard.json content
   - Mount ConfigMap to Grafana dashboard provisioning directory
   - Auto-load dashboard on Grafana startup

5. **Security Considerations**:
   - Change default admin password (environment-specific)
   - Basic username/password authentication for now (Azure AD deferred to future)
   - Use cert-manager for SSL/TLS certificates (HTTPS from the start)

### Alternative Approaches Considered

1. **Grafana with Ingress Controller**:
   - Deploy nginx-ingress or similar
   - **Rejected**: Adds complexity; LoadBalancer pattern already established for Keycloak
   
2. **Grafana without TLS/HTTPS**:
   - Deploy with HTTP only initially
   - **Rejected**: Not secure for external access; use cert-manager from the start for proper security
   
3. **Single Shared Grafana Instance**:
   - Deploy one Grafana for all customers
   - **Rejected**: Violates multi-tenant isolation pattern; each customer needs isolated monitoring

4. **Embed Grafana in Keycloak Pod**:
   - Sidecar container pattern
   - **Rejected**: Tight coupling; separate concerns better for scalability

## Success Criteria

- [ ] Grafana deployed successfully via Helm in `monitoring` namespace
- [ ] Grafana accessible externally via LoadBalancer with predictable DNS name
- [ ] Prometheus configured automatically as Grafana data source
- [ ] Keycloak dashboard (keycloak-dashboard.json) pre-loaded and functional
- [ ] Dashboard displays live metrics from Keycloak (JVM, connections, CPU, memory)
- [ ] Works across all deployment environments (dev, prod, customer)
- [ ] No manual configuration steps required after Terraform apply
- [ ] Admin credentials set securely via Terraform variables
- [ ] Persistent storage configured to retain dashboards and settings
- [ ] Documentation updated with Grafana access instructions

## Risks & Mitigation

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Dashboard JSON format incompatible with Grafana version | Medium - Dashboard fails to load | Low | Test with target Grafana version; update JSON format if needed |
| LoadBalancer costs exceed budget | Medium - Additional Azure costs | Low | LoadBalancer already used for Keycloak; marginal cost increase |
| Dashboard requires data source UID mismatch | Medium - Metrics don't display | Medium | Template the dashboard JSON to inject correct data source UID |
| Persistent volume claims fail in AKS | High - Configuration lost on restart | Low | Use Azure Disk storage class; test PVC creation |
| Grafana version incompatibility with Prometheus | Medium - Data source connection fails | Low | Use stable, tested versions of both charts |
| cert-manager certificate issuance fails | High - HTTPS access unavailable | Low | Use existing ClusterIssuer; test in dev first |
| Public exposure security concerns | Medium - Unauthorized access | Low | Use HTTPS with cert-manager; set strong admin password |

## Dependencies

- Prometheus already deployed in `monitoring` namespace (✅ implemented)
- Keycloak exposing metrics on port 9000 (✅ configured)
- cert-manager deployed with ClusterIssuer configured (✅ used for Keycloak)
- Azure DNS Zone for CNAME record creation (✅ available)
- Kubernetes cluster with persistent volume support (✅ AKS with Azure Disk)
- Helm provider configured in Terraform (✅ already configured)

## Estimated Effort

- **Design & Planning**: 2 hours (✅ completed with this proposal)
- **Implementation**: 6-8 hours
  - Terraform resources (Helm release, LoadBalancer, DNS): 3 hours
  - Grafana values file creation: 1 hour
  - Dashboard ConfigMap and provisioning: 2 hours
  - Testing across environments: 2 hours
- **Documentation**: 1 hour
- **Total**: ~9-11 hours

## Impact Analysis

### Affected Components
- **New**: `terraform/modules/trustorbs/telemetry/grafana-values.yaml`
- **New**: `terraform/modules/trustorbs/telemetry/keycloak-dashboard.json`
- **New**: `terraform/modules/trustorbs/cert-manager/grafana-certificate.yaml` (TLS certificate)
- **Modified**: `terraform/modules/trustorbs/main.tf` (add Grafana Helm release, LoadBalancer, DNS, Certificate)
- **Modified**: `terraform/modules/trustorbs/variables.tf` (add Grafana admin password variable)
- **Modified**: `terraform/environments/*/main.tf` (pass Grafana credentials)

### Breaking Changes
- **None**: This is an additive change with no impact on existing resources

### Migration Path
- No migration required; this is a new capability
- Existing deployments can be updated by running `terraform apply`

## Open Questions

1. Should we enable anonymous access for read-only dashboards?
   - **Answer**: No, require username/password authentication for all access initially
   
2. Should we set up Grafana alerting to AlertManager?
   - **Answer**: Defer AlertManager integration to future phase; focus on visualization first
   
3. Should we use Azure AD integration for Grafana authentication?
   - **Answer**: Defer to future enhancement; use basic auth (username/password) initially

4. What SSL/TLS approach should be used for external access?
   - **Answer**: Use cert-manager to provision TLS certificates for Grafana subdomain, following the existing Keycloak pattern

5. Should dashboard be editable or read-only?
   - **Answer**: Yes, allow editing in UI. Templates deployed from config but users can customize. Changes should be exported back to repository for version control.
