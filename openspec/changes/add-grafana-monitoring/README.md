# Add Grafana Monitoring

This change proposal adds Grafana as a visualization layer for monitoring Keycloak metrics collected by Prometheus.

## Status: Draft

## Quick Links

- **[Proposal](./proposal.md)**: Why we need Grafana, benefits, and success criteria
- **[Design](./design.md)**: Technical decisions, architecture, and implementation approach
- **[Tasks](./tasks.md)**: Step-by-step implementation checklist (16 sections, 100+ tasks)
- **[Spec Delta](./specs/monitoring-stack/spec.md)**: Formal requirements for the monitoring stack capability

## Overview

Currently, TrustOrbs deploys Prometheus to collect Keycloak metrics, but there's no user-friendly visualization layer. This proposal adds Grafana with:

- **External accessibility** via Azure LoadBalancer
- **Pre-configured Keycloak dashboard** with 40+ metric panels
- **Automatic Prometheus integration** via Kubernetes DNS
- **Multi-tenant isolation** with per-deployment Grafana instances
- **Persistent storage** for dashboard and configuration retention

## Key Files to Review

### 1. Start Here: [proposal.md](./proposal.md)
Read this first to understand the problem, solution, and impact.

### 2. Technical Details: [design.md](./design.md)
Deep dive into technical decisions:
- Why LoadBalancer over Ingress?
- How dashboard provisioning works
- Data source configuration approach
- Security considerations

### 3. Implementation Guide: [tasks.md](./tasks.md)
Complete checklist organized into 16 phases:
- Terraform resources
- Helm configuration
- Dashboard preparation
- Testing procedures
- Production deployment

### 4. Formal Specification: [specs/monitoring-stack/spec.md](./specs/monitoring-stack/spec.md)
Formal requirements with scenarios for:
- Grafana deployment and accessibility
- Dashboard provisioning
- Prometheus integration
- Persistent storage
- Multi-tenant isolation

## What Gets Created

### New Files
```
terraform/modules/trustorbs/telemetry/
├── grafana-values.yaml          # Helm values for Grafana
└── keycloak-dashboard.json      # Pre-configured dashboard
```

### Modified Files
```
terraform/modules/trustorbs/
├── main.tf                      # Add Grafana Helm release, LoadBalancer, DNS
└── variables.tf                 # Add grafana_admin_username/password

terraform/environments/*/
└── main.tf                      # Pass Grafana credentials
```

## Architecture

```
User Browser → DNS (grafana-${prefix}.example.com)
              ↓
          Azure LoadBalancer
              ↓
          Grafana (monitoring namespace)
              ↓
          Prometheus (internal)
              ↓
          Keycloak Metrics (port 9000)
```

## Success Metrics

- ✅ Grafana accessible externally without kubectl
- ✅ Keycloak dashboard pre-loaded with 40+ panels
- ✅ Live metrics displayed from Prometheus
- ✅ Multi-tenant isolation maintained
- ✅ Configuration persists across pod restarts
- ✅ Zero manual configuration required

## Estimated Effort

- **Total**: 9-11 hours
- **Terraform**: 3 hours
- **Configuration**: 3 hours
- **Testing**: 3-4 hours
- **Documentation**: 1 hour

## Next Steps

1. **Review**: Read proposal.md and design.md
2. **Approve**: Get team sign-off on technical approach
3. **Implement**: Follow tasks.md checklist
4. **Test**: Validate in dev environment first
5. **Deploy**: Roll out to prod after validation

## Validation

```bash
openspec validate add-grafana-monitoring --strict
```

**Status**: ✅ Passed (all requirements have scenarios, proper formatting)

## Questions or Feedback?

- Review the "Open Questions" section in [proposal.md](./proposal.md#open-questions)
- Check "Risks & Mitigation" in [design.md](./design.md#risks--trade-offs)
- Consult the detailed [tasks checklist](./tasks.md) for implementation details
