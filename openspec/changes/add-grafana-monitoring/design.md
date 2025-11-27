# Design: Grafana Monitoring Integration

## Context

The TrustOrbs infrastructure currently deploys Prometheus for metrics collection from Keycloak instances but lacks a visualization layer for operational monitoring. This design describes the technical approach for integrating Grafana as the visualization and dashboarding solution, following the established patterns in the codebase for multi-tenant isolation, external service exposure, and Helm-based deployments.

### Background
- Prometheus already scrapes Keycloak metrics on port 9000 (`/auth/metrics`)
- A comprehensive Keycloak dashboard JSON exists from local Docker testing
- Existing LoadBalancer pattern used for Keycloak can be replicated for Grafana
- Multi-tenant deployments require isolated monitoring per customer

### Constraints
- Must follow existing Terraform patterns and module structure
- Must support multi-tenant isolation (separate Grafana per deployment)
- Must use Helm for Grafana deployment (consistent with other components)
- Must expose externally via LoadBalancer (no Ingress controller available)
- Must work in Azure AKS with Azure DNS
- Should minimize manual post-deployment configuration

### Stakeholders
- **Operations Teams**: Need easy access to dashboards without kubectl knowledge
- **DevOps Engineers**: Maintain Terraform infrastructure
- **Support Engineers**: Monitor customer Keycloak health and performance
- **Customers**: Benefit from improved uptime through better monitoring

## Goals / Non-Goals

### Goals
1. Deploy Grafana via Helm in the `monitoring` namespace
2. Expose Grafana externally via Azure LoadBalancer with predictable DNS
3. Auto-configure Prometheus as Grafana data source
4. Auto-provision Keycloak dashboard from JSON
5. Configure persistent storage for dashboard retention
6. Support multi-tenant isolation with per-deployment Grafana instances
7. Secure with basic authentication (admin username/password)

### Non-Goals
1. ~~Implement Azure AD/OAuth integration~~ (future enhancement - basic auth for now)
2. ~~Configure AlertManager integration~~ (deferred to future phase)
3. ~~Create multiple pre-built dashboards~~ (focus on Keycloak dashboard only)
4. ~~Implement Grafana HA/clustering~~ (single instance sufficient for current scale)
5. ~~Custom Grafana plugins~~ (use standard installation)

## Technical Decisions

### Decision 1: Helm Chart Selection
**Choice**: Use official `grafana/grafana` Helm chart from Grafana Labs

**Rationale**:
- Official chart with active maintenance and community support
- Consistent with pattern of using official/well-maintained charts (cert-manager, prometheus-community)
- Provides extensive configuration options via values.yaml
- Built-in support for dashboard provisioning and data source configuration

**Alternatives Considered**:
- **Bitnami Grafana Chart**: More opinionated; rejected to stay consistent with official sources
- **Custom Deployment**: Too much maintenance burden; Helm chart handles complexity

### Decision 2: External Exposure via LoadBalancer
**Choice**: Create Kubernetes LoadBalancer service for Grafana, similar to Keycloak pattern

**Rationale**:
- Matches existing Keycloak exposure pattern for consistency
- No Ingress controller deployed; LoadBalancer is simpler
- Provides direct external access without additional layers
- Azure DNS label annotation gives predictable FQDN

**Alternatives Considered**:
- **ClusterIP + Port Forwarding**: Rejected; requires kubectl access, not user-friendly
- **Ingress Controller**: Rejected; adds complexity, additional component to maintain
- **NodePort**: Rejected; less secure, requires firewall rules, non-standard ports

**Implementation**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: grafana-loadbalancer
  namespace: monitoring
  annotations:
    service.beta.kubernetes.io/azure-dns-label-name: "grafana-${local.prefix}"
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: grafana
  ports:
    - port: 3000
      targetPort: 3000
      protocol: TCP
```

### Decision 3: Dashboard Provisioning Strategy
**Choice**: Use Kubernetes ConfigMap with Grafana dashboard provisioning directory, with dashboards configured as editable

**Rationale**:
- Grafana supports automatic dashboard discovery from provisioning directories
- ConfigMap can be templated with Terraform to inject dashboard JSON
- No manual import steps required post-deployment
- Dashboard survives Grafana pod restarts
- Dashboards set to `editable: true` allows UI modifications
- Users can customize dashboards and export changes back to Git for version control

**Alternatives Considered**:
- **Manual Import**: Rejected; requires post-deployment steps, not automated
- **Grafana API Import**: Rejected; requires scripting, adds complexity
- **Persistent Storage Only**: Rejected; doesn't handle initial provisioning
- **Read-Only Dashboards**: Rejected; operations teams need ability to customize

**Implementation**:
```hcl
resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "grafana-dashboards"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "keycloak-metrics.json" = file("${path.module}/telemetry/keycloak-dashboard.json")
  }
}
```

### Decision 4: Prometheus Data Source Configuration
**Choice**: Auto-configure Prometheus data source using Grafana Helm values with internal Kubernetes DNS

**Rationale**:
- Both services in same cluster; internal DNS is reliable and fast
- No network egress costs
- Helm chart supports datasources configuration in values.yaml
- Kubernetes service discovery handles Prometheus location

**Data Source URL**: `http://prometheus-server.monitoring.svc.cluster.local`

**Alternatives Considered**:
- **External Prometheus URL**: Rejected; unnecessary when both in cluster
- **Manual Configuration**: Rejected; not automated, error-prone

**Implementation in grafana-values.yaml**:
```yaml
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        url: http://prometheus-server.monitoring.svc.cluster.local
        access: proxy
        isDefault: true
        jsonData:
          httpMethod: POST
          timeInterval: 15s
```

### Decision 5: Persistent Storage Configuration
**Choice**: Enable persistent volume with Azure Disk storage class, 10Gi size

**Rationale**:
- Retains dashboard customizations, user configs, and data source settings
- Azure Disk is default storage class in AKS, reliable
- 10Gi sufficient for dashboard storage (Grafana stores data sources/dashboards as SQLite DB)
- Follows Prometheus pattern which also uses persistent storage

**Alternatives Considered**:
- **emptyDir (No Persistence)**: Rejected; loses customizations on restart
- **Azure Files**: Rejected; overkill for single-pod Grafana, more expensive
- **Larger Volume**: Rejected; 10Gi sufficient, can scale later if needed

### Decision 6: Authentication Strategy
**Choice**: Basic authentication with admin username/password from Terraform variables

**Rationale**:
- Simple to implement and configure
- Sufficient security for internal operations teams
- Credentials can be environment-specific (different for dev/prod)
- Azure AD integration can be added later without breaking change

**Alternatives Considered**:
- **Anonymous Access**: Rejected; security risk, no audit trail
- **Azure AD Integration**: Deferred; adds complexity, can be future enhancement
- **OAuth/OIDC with Keycloak**: Deferred; creates circular dependency

**Implementation**:
```yaml
admin:
  existingSecret: ""
  userKey: admin-user
  passwordKey: admin-password
env:
  GF_SECURITY_ADMIN_USER: ${grafana_admin_username}
  GF_SECURITY_ADMIN_PASSWORD: ${grafana_admin_password}
```

**Future Enhancement Note**: Azure AD integration should be considered for production environments to provide SSO and better audit logging.

### Decision 6.5: External Access & SSL/TLS with cert-manager
**Choice**: Use cert-manager to provision TLS certificates for Grafana subdomain, following the Keycloak pattern

**Rationale**:
- cert-manager already deployed and managing certificates for Keycloak
- Consistent security approach across all externally exposed services
- Automated certificate lifecycle management (issuance, renewal)
- Industry best practice to use HTTPS for externally exposed services
- Grafana subdomain follows pattern: `grafana-${prefix}.${dns_zone}`
- Can leverage existing ClusterIssuer configuration

**Alternatives Considered**:
- **HTTP Only**: Rejected; not secure for external access, credentials transmitted in clear text
- **Azure Application Gateway**: Rejected; adds complexity and cost
- **Manual Certificate Management**: Rejected; cert-manager automates this
- **Wildcard Certificate**: Evaluate if existing setup uses wildcard; otherwise create specific cert

**Implementation Approach**:
1. Review existing cert-manager ClusterIssuer (likely Let's Encrypt)
2. Create Certificate resource for Grafana subdomain
3. Configure LoadBalancer to use TLS with certificate secret
4. Update Grafana values to configure TLS settings
5. DNS and certificate validation handled by cert-manager

### Decision 7: Dashboard Data Source UID Handling
**Choice**: Template dashboard JSON to replace data source UID with `${DS_PROMETHEUS}` variable

**Rationale**:
- Dashboard JSON from Docker setup references specific data source UID
- Grafana provisioning supports `${DS_PROMETHEUS}` variable substitution
- Helm chart can configure data source name to match variable

**Alternatives Considered**:
- **Fixed UID**: Rejected; brittle, breaks if data source recreated
- **Manual Edit**: Rejected; not automated
- **Remove UID**: Rejected; dashboard may fail to resolve data source

**Implementation**: Update all `"datasource": {"uid": "..."}` in dashboard JSON to `"datasource": "${DS_PROMETHEUS}"`

## Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Cloud (East US)                     │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              AKS Cluster (aks-${prefix})            │    │
│  │                                                      │    │
│  │  ┌───────────────────────────────────────────────┐  │    │
│  │  │         Namespace: monitoring                 │  │    │
│  │  │                                               │  │    │
│  │  │  ┌─────────────┐      ┌──────────────────┐   │  │    │
│  │  │  │ Prometheus  │      │    Grafana       │   │  │    │
│  │  │  │   Server    │◄─────┤  (Port 3000)     │   │  │    │
│  │  │  │             │      │                  │   │  │    │
│  │  │  │  ClusterIP  │      │  Dashboards:     │   │  │    │
│  │  │  │  (internal) │      │  - Keycloak      │   │  │    │
│  │  │  └─────────────┘      │                  │   │  │    │
│  │  │         ▲              └───────┬──────────┘   │  │    │
│  │  │         │                      │              │  │    │
│  │  │         │                      ▼              │  │    │
│  │  │         │              ┌──────────────────┐   │  │    │
│  │  │         │              │  LoadBalancer    │   │  │    │
│  │  │         │              │  Service         │   │  │    │
│  │  │         │              └─────────┬────────┘   │  │    │
│  │  └─────────┼────────────────────────┼────────────┘  │    │
│  │            │                        │               │    │
│  │  ┌─────────┴────────────┐           │               │    │
│  │  │ Namespace: default   │           │               │    │
│  │  │                      │           │               │    │
│  │  │  ┌────────────────┐  │           │               │    │
│  │  │  │   Keycloak     │  │           │               │    │
│  │  │  │  (Port 9000)   │  │           │               │    │
│  │  │  │    Metrics     │──┘           │               │    │
│  │  │  └────────────────┘              │               │    │
│  │  └─────────────────────────────────┘               │    │
│  └──────────────────────────────────────┬──────────────┘    │
│                                         │                   │
│                                         ▼                   │
│                          ┌──────────────────────────┐       │
│                          │  Azure LoadBalancer      │       │
│                          │  grafana-${prefix}       │       │
│                          │  .eastus.cloudapp.azure  │       │
│                          └──────────────────────────┘       │
│                                         │                   │
└─────────────────────────────────────────┼───────────────────┘
                                          │
                                          ▼
                          ┌──────────────────────────┐
                          │     Azure DNS Zone       │
                          │   CNAME Record:          │
                          │   grafana-${prefix}      │
                          └──────────────────────────┘
                                          │
                                          ▼
                              Operations Team Browser
```

### Data Flow

1. **Metrics Collection**:
   - Keycloak exposes metrics on port 9000 at `/auth/metrics`
   - Prometheus scrapes metrics every 15 seconds
   - Metrics stored in Prometheus time-series database

2. **Dashboard Access**:
   - User navigates to `http://grafana-${prefix}.${dns_zone_name}:3000`
   - DNS resolves CNAME to Azure LoadBalancer FQDN
   - LoadBalancer forwards to Grafana service in `monitoring` namespace
   - Grafana serves login page (if not authenticated)

3. **Dashboard Queries**:
   - Grafana dashboard panels query Prometheus data source
   - Queries sent to `http://prometheus-server.monitoring.svc.cluster.local`
   - Prometheus returns time-series data for requested metrics
   - Grafana renders visualizations in dashboard panels

4. **Dashboard Provisioning**:
   - Grafana starts, reads provisioning directory
   - Discovers ConfigMap-mounted dashboard JSON
   - Imports dashboard into SQLite database
   - Dashboard available in UI immediately

## Implementation Plan

### Phase 1: Terraform Resources (Core Infrastructure)
1. Add Grafana admin credentials to Terraform variables
2. Create Grafana Helm release resource in `main.tf`
3. Create Grafana LoadBalancer service resource
4. Create Azure DNS CNAME record for Grafana
5. Add Grafana URL to Terraform outputs

### Phase 2: Grafana Configuration (Values File)
1. Create `grafana-values.yaml` in `telemetry/` directory
2. Configure Prometheus data source in values file
3. Configure persistent storage (10Gi PVC)
4. Configure admin credentials from variables
5. Configure dashboard provisioning directory

### Phase 3: Dashboard Provisioning (ConfigMap)
1. Copy `keycloak-dashboard.json` to `telemetry/` directory
2. Update dashboard JSON to use `${DS_PROMETHEUS}` variable
3. Create Kubernetes ConfigMap resource with dashboard JSON
4. Configure Helm values to mount ConfigMap

### Phase 4: Testing & Validation
1. Test deployment in dev environment
2. Verify Grafana accessible via LoadBalancer URL
3. Verify Prometheus data source connectivity
4. Verify dashboard loads and displays metrics
5. Test persistence (restart Grafana pod, verify dashboard retained)
6. Test multi-tenant isolation (deploy multiple instances)

## Risks / Trade-offs

### Risk 1: Dashboard JSON Compatibility
- **Risk**: Dashboard JSON format may be incompatible with target Grafana version
- **Impact**: Medium - Dashboard fails to load or renders incorrectly
- **Mitigation**: Test with target Grafana version (latest stable); update JSON format if needed
- **Trade-off**: Using latest stable Grafana vs pinning to specific version for compatibility

### Risk 2: Data Source UID Resolution
- **Risk**: Dashboard data source UID may not resolve to Prometheus
- **Impact**: Medium - Dashboard panels show "No data" or errors
- **Mitigation**: Use `${DS_PROMETHEUS}` variable, configure data source name to match
- **Trade-off**: Templating dashboard JSON vs keeping original format

### Risk 3: LoadBalancer Costs
- **Risk**: Additional LoadBalancer increases Azure costs
- **Impact**: Low - Marginal cost increase (~$20-30/month per deployment)
- **Mitigation**: Already using LoadBalancer for Keycloak; pattern established
- **Trade-off**: Cost vs ease of access (no kubectl knowledge required)

### Risk 4: Public Exposure Security
- **Risk**: Grafana publicly accessible may attract unauthorized access attempts
- **Impact**: Medium - Potential security risk if credentials weak
- **Mitigation**: Enforce strong admin passwords via Terraform validation, document need for Azure AD in future
- **Trade-off**: Ease of access vs security (future Azure AD integration recommended)

### Risk 5: Persistent Volume Failures
- **Risk**: Azure Disk PVC may fail to provision or mount
- **Impact**: High - Grafana fails to start or loses data
- **Mitigation**: Test PVC creation in dev, use default AKS storage class
- **Trade-off**: Managed disk cost vs reliability (Azure Disk is reliable, worth the cost)

## Migration Plan

This is a new capability with no existing Grafana deployment, so no migration is required.

### Deployment Steps
1. Update Terraform code in feature branch
2. Run `terraform plan` in dev environment to preview changes
3. Review plan for correctness (new resources, no deletions)
4. Run `terraform apply` in dev environment
5. Validate Grafana deployment and dashboard functionality
6. Deploy to prod environment after dev validation
7. Update documentation with Grafana access instructions

### Rollback Plan
If issues arise:
1. Remove Grafana Helm release: `terraform destroy -target=helm_release.grafana`
2. Remove LoadBalancer service and DNS record
3. Investigate issue, fix in code
4. Re-apply Terraform configuration

## Open Questions

1. **Q: Should we set resource limits for Grafana pods?**
   - **A**: Yes, add reasonable defaults (CPU: 100m-500m, Memory: 256Mi-512Mi)

2. **Q: Should we enable Grafana alerting rules?**
   - **A**: No, Prometheus handles alerting; Grafana focuses on visualization

3. **Q: Should we configure Grafana SMTP for email notifications?**
   - **A**: Defer to future; focus on dashboard visualization first

4. **Q: Should we support custom dashboard uploads?**
   - **A**: Yes, via Grafana UI; persistent storage retains user-uploaded dashboards

5. **Q: Should we version the dashboard JSON in Git?**
   - **A**: Yes, store in `telemetry/keycloak-dashboard.json` for version control and collaboration
