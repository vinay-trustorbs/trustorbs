# Change: Migrate Bitnami PostgreSQL to CloudNativePG

## Why

Bitnami has moved its Helm charts behind a paywall, blocking automated deployments and breaking existing infrastructure. Current dev environment deployments are failing due to inability to pull `bitnami/postgresql` chart. CloudNativePG provides an open-source, operator-based, HA-ready PostgreSQL solution that is compatible with the codecentric keycloakx chart and offers better operational capabilities for production environments.

## What Changes

- **BREAKING**: Replace Bitnami PostgreSQL Helm chart with CloudNativePG Operator and CRD-based cluster deployment
- Add CloudNativePG operator installation to Terraform module
- Replace `helm_release.keycloak-db` with CloudNativePG `Cluster` custom resource
- Update Keycloak configuration to use CloudNativePG auto-generated secrets and service endpoints
- Maintain backward compatibility with existing database schema and data
- Enable future HA scalability (3+ instances) while starting with single instance for dev
- Add data migration procedures for existing deployments
- Update documentation and runbooks for new database management approach

## Impact

**Affected Specs:**
- `database-management` (new capability)

**Affected Code:**
- `terraform/modules/trustorbs/main.tf` - Replace PostgreSQL helm release with CloudNativePG cluster
- `terraform/modules/trustorbs/keycloak/keycloak-db-values.yaml` - Deprecated (replaced by CloudNativePG cluster manifest)
- `terraform/modules/trustorbs/keycloak/keycloak-server-values.yaml` - Update secret references and connection configuration
- `terraform/modules/trustorbs/keycloak/https-keycloak-server-values.yaml` - Update secret references and connection configuration
- New files:
  - `terraform/modules/trustorbs/database/cloudnativepg-operator-values.yaml` - Operator configuration
  - `terraform/modules/trustorbs/database/postgres-cluster.yaml` - Development cluster configuration
  - `terraform/modules/trustorbs/database/postgres-cluster-ha.yaml` - Production HA cluster configuration (reference)

**Deployment Impact:**
- **Immediate**: Fixes broken dev environment deployments
- **Breaking Change**: Requires data migration for existing environments
- **Downtime**: 5-30 minutes for migration (depending on database size)
- **Rollback**: Keep Bitnami deployment scaled down for 7 days post-migration
- **Testing**: Full migration dry run required before production deployment

**Operational Changes:**
- New operator-managed PostgreSQL clusters
- Different secret structure (CloudNativePG auto-generates with `<cluster-name>-app` naming)
- New service endpoints (`<cluster-name>-rw`, `<cluster-name>-ro`, `<cluster-name>-r`)
- Backup/restore operations change to Barman-based approach
- HA scaling available for production (future capability)

**Benefits:**
- ✅ Resolves Bitnami paywall issue
- ✅ Open-source, community-maintained solution
- ✅ Operator-based management (automated backups, failover, monitoring)
- ✅ HA-ready architecture for production scalability
- ✅ Better monitoring integration (Prometheus PodMonitor)
- ✅ Consistent with cloud-native Kubernetes patterns
