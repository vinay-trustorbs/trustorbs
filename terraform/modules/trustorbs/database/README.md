# Database Management with CloudNativePG

This directory contains the configuration for managing PostgreSQL databases using the CloudNativePG operator.

## Overview

CloudNativePG is a Kubernetes operator that manages the full lifecycle of PostgreSQL clusters. It provides:
- Automated PostgreSQL cluster provisioning
- Automatic secret generation for database credentials
- Multiple service endpoints (read-write, read-only, any-instance)
- High availability with automatic failover
- Built-in monitoring with Prometheus integration

## Files

### `cloudnativepg-operator-values.yaml`
Helm values for deploying the CloudNativePG operator:
- Enables Prometheus monitoring
- Configures resource limits
- Sets up namespace watching

### `keycloak-database-cluster.yaml`
CloudNativePG Cluster manifest template for Keycloak's PostgreSQL database:
- Configurable instance count (1 for dev, 3 for production HA)
- Configurable storage size
- Auto-creates "keycloak" database with "keycloak" user
- Generates secret "keycloak-database-app" with connection credentials
- Creates service endpoints:
  - `keycloak-database-rw` - Read-write (primary)
  - `keycloak-database-ro` - Read-only (replicas)
  - `keycloak-database-r` - Any instance

## Services

When the cluster is deployed, three Kubernetes services are automatically created:

1. **keycloak-database-rw** - Routes to primary instance for read-write operations
2. **keycloak-database-ro** - Routes to replica instances for read-only operations
3. **keycloak-database-r** - Routes to any available instance

## Secrets

The operator automatically generates a secret named `keycloak-database-app` containing:
- `username` - Database username (keycloak)
- `password` - Auto-generated secure password
- `dbname` - Database name (keycloak)
- `host` - Service hostname (keycloak-database-rw.default.svc.cluster.local)
- `port` - PostgreSQL port (5432)
- `uri` - Full connection URI
- `jdbc-uri` - JDBC connection string

## Configuration Variables

The cluster manifest uses Terraform variables:
- `database_instances` - Number of PostgreSQL instances (default: 1)
- `database_storage_size` - Storage size per instance (default: 20Gi)

## Deployment Flow

1. **CloudNativePG Operator** - Deployed to `cnpg-system` namespace
2. **PostgreSQL Cluster** - Deployed to `default` namespace after operator is ready
3. **Keycloak** - Deployed after PostgreSQL cluster is healthy

## Migration from Bitnami PostgreSQL

To migrate from existing Bitnami PostgreSQL:

1. Backup existing database:
   ```bash
   kubectl exec -it keycloak-db-postgresql-0 -- pg_dump -U dbusername keycloak > backup.sql
   ```

2. Apply Terraform changes to deploy CloudNativePG

3. Wait for cluster to be ready:
   ```bash
   kubectl wait --for=condition=Ready cluster/keycloak-database --timeout=600s
   ```

4. Restore data to new cluster:
   ```bash
   kubectl exec -it keycloak-database-1 -- psql -U keycloak keycloak < backup.sql
   ```

5. Keycloak will automatically use the new database

## Monitoring

The cluster is configured with Prometheus monitoring enabled. Metrics are exposed via PodMonitor and include:
- `cnpg_pg_database_size_bytes` - Database size
- `cnpg_backends_total` - Number of active connections
- `cnpg_pg_replication_lag` - Replication lag (HA deployments)

## High Availability (Production)

For production deployments with HA:
- Set `database_instances = 3` (1 primary + 2 replicas)
- Pods are spread across nodes using anti-affinity rules
- Automatic failover is enabled with `primaryUpdateStrategy: unsupervised`
- Read traffic can be distributed to replicas using `-ro` service

## Troubleshooting

Check cluster status:
```bash
kubectl get cluster keycloak-database
kubectl describe cluster keycloak-database
```

Check PostgreSQL pods:
```bash
kubectl get pods -l cnpg.io/cluster=keycloak-database
kubectl logs keycloak-database-1
```

Check operator logs:
```bash
kubectl logs -n cnpg-system deployment/cloudnativepg-controller-manager
```

Verify secret was created:
```bash
kubectl get secret keycloak-database-app
kubectl describe secret keycloak-database-app
```

Test database connection:
```bash
kubectl exec -it keycloak-database-1 -- psql -U keycloak keycloak
```
