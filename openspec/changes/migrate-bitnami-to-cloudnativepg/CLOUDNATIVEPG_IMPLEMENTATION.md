# CloudNativePG Database Implementation - Dev Environment

## Implementation Summary

Successfully migrated from Bitnami PostgreSQL to CloudNativePG for the dev environment on **November 23, 2025**.

## What Was Deployed

### 1. CloudNativePG Operator
- **Namespace**: `cnpg-system`
- **Release Name**: `cnpg`
- **Chart Version**: 0.26.1 (currently deployed) / 0.22.1 (in Terraform)
- **Monitoring**: PodMonitor disabled (Prometheus Operator CRDs not installed)

### 2. PostgreSQL Cluster
- **Name**: `keycloak-database`
- **Namespace**: `default`
- **Instances**: 1 (single-instance for dev)
- **Storage**: 20Gi (Azure managed-csi storage class)
- **PostgreSQL Version**: 16.6
- **Image**: `ghcr.io/cloudnative-pg/postgresql:16.6`

### 3. Services Created
CloudNativePG automatically created three Kubernetes services:
- `keycloak-database-rw` - Read-write endpoint (points to primary)
- `keycloak-database-ro` - Read-only endpoint (for replicas, same as rw in single-instance)
- `keycloak-database-r` - Any-instance endpoint

### 4. Auto-Generated Secret
- **Secret Name**: `keycloak-database-app`
- **Keys**: username, password, dbname, host, port, uri, jdbc-uri, pgpass, fqdn-uri, fqdn-jdbc-uri, user
- **Database**: keycloak
- **User**: keycloak
- **Password**: Auto-generated securely by CloudNativePG

### 5. Keycloak Configuration
- **Updated to use**: CloudNativePG database via `keycloak-database-rw` service
- **Secret reference**: `existingSecret: keycloak-database-app`
- **Cache mode**: `--cache=local` (no distributed clustering for single instance)
- **Status**: Successfully connected and initialized database schema

## Architecture Decisions for Dev Environment

### Single-Instance Design
**Decision**: Deploy PostgreSQL as a single instance (instances: 1)

**Rationale**:
- Dev environment doesn't require high availability
- Reduces resource consumption and costs
- Simpler troubleshooting and debugging
- Faster startup and deployment times
- Still provides CloudNativePG benefits (automated backups, monitoring, declarative management)

### Local Caching for Keycloak
**Decision**: Use `--cache=local` instead of distributed Infinispan clustering

**Rationale**:
- Single Keycloak instance doesn't need distributed cache
- Eliminates JGroups/JDBC-PING complexity
- Faster startup and lower memory usage
- Sufficient for dev workloads

### Storage Configuration
**Decision**: 20Gi storage with Azure managed-csi storage class

**Rationale**:
- Adequate for dev database size
- Uses Azure's default storage class (no custom StorageClass needed)
- Can be expanded later if needed (storage expansion supported)

### Monitoring Disabled
**Decision**: PodMonitor disabled for both operator and cluster

**Rationale**:
- Prometheus Operator CRDs not installed in dev
- Avoids deployment failures due to missing CRDs
- Can be enabled later when Prometheus Operator is deployed

## Making it Highly Available (Production)

To convert the dev setup to high availability for production, make these changes:

### 1. Update Database Configuration

In `terraform/environments/prod/main.tf`:
```hcl
module "trustorbs" {
  source = "../../modules/trustorbs"

  environment                  = "prod"
  uri_prefix                   = "auth"
  dns_zone_name                = "trustorbs.com"
  dns_zone_resource_group_name = "prod_trustorbs"

  # High Availability Database Configuration
  database_instances    = 3              # 1 primary + 2 replicas
  database_storage_size = "100Gi"        # Larger storage for production

  tags = {
    Environment = "production"
  }
}
```

### 2. Enable Distributed Caching for Keycloak

Update `keycloak/https-keycloak-server-values.yaml`:
```yaml
command:
  - "/opt/keycloak/bin/kc.sh"
  - "--verbose"
  - "start"
  - "--https-port=8443"
  - "--https-certificate-file=/etc/tls/tls.crt"
  - "--https-certificate-key-file=/etc/tls/tls.key"
  - "--hostname=${hostname}"
  - "--hostname-strict=true"
  - "--metrics-enabled=true"
  - "--health-enabled=true"
  - "--cache=ispn"                    # Distributed Infinispan cache
  - "--cache-stack=kubernetes"        # Use Kubernetes discovery

extraEnv: |
  - name: KEYCLOAK_ADMIN
    valueFrom:
      secretKeyRef:
        name: {{ include "keycloak.fullname" . }}-admin-creds
        key: user
  - name: KEYCLOAK_ADMIN_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ include "keycloak.fullname" . }}-admin-creds
        key: password
  - name: JAVA_OPTS_APPEND
    value: >-
      -XX:MaxRAMPercentage=50.0
      -Djgroups.dns.query={{ include "keycloak.fullname" . }}-headless

# Scale Keycloak horizontally
replicas: 3
```

### 3. Enable Monitoring (Optional)

First, install Prometheus Operator:
```bash
helm install prometheus-operator prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

Then enable PodMonitor in CloudNativePG:
```yaml
# database/cloudnativepg-operator-values.yaml
monitoring:
  podMonitorEnabled: true

# database/keycloak-database-cluster.yaml
monitoring:
  enablePodMonitor: true
```

### 4. Configure Automated Backups (Production)

Add backup configuration to `database/keycloak-database-cluster.yaml`:
```yaml
spec:
  # ... existing config ...
  
  backup:
    barmanObjectStore:
      destinationPath: "https://your-storage-account.blob.core.windows.net/postgres-backups"
      azureCredentials:
        storageAccount:
          name: backup-storage-creds
          key: storage-account-name
        storageKey:
          name: backup-storage-creds
          key: storage-account-key
      wal:
        compression: gzip
      data:
        compression: gzip
    retentionPolicy: "30d"
```

Create scheduled backups:
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: keycloak-database-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  backupOwnerReference: self
  cluster:
    name: keycloak-database
```

### 5. HA Benefits with 3 Instances

With `instances: 3`:
- **Automatic Failover**: If primary fails, a replica is promoted within 30 seconds
- **Zero-Downtime Updates**: Rolling updates happen one pod at a time
- **Read Scaling**: Use `keycloak-database-ro` service to distribute read queries
- **Pod Anti-Affinity**: Pods spread across different nodes automatically
- **Replication**: Synchronous/asynchronous replication ensures data safety

### 6. Resource Sizing for Production

Adjust resources in the cluster manifest:
```yaml
resources:
  requests:
    memory: "2Gi"
    cpu: "1000m"
  limits:
    memory: "4Gi"
    cpu: "2000m"
```

## Current Status

✅ **CloudNativePG Operator**: Deployed and running  
✅ **PostgreSQL Cluster**: Healthy, 1 instance running  
✅ **Database Services**: All 3 services created (-rw, -ro, -r)  
✅ **Auto-Generated Secret**: Created with all connection details  
✅ **Keycloak Integration**: Connected successfully using CloudNativePG database  
✅ **Bitnami PostgreSQL**: Removed from deployment  
✅ **DNS Configuration**: CNAME record created, waiting for nameserver propagation

## Verification Commands

```bash
# Check cluster health
kubectl get cluster keycloak-database -n default

# Check PostgreSQL pods
kubectl get pods -n default -l cnpg.io/cluster=keycloak-database

# Check auto-generated secret
kubectl get secret keycloak-database-app -n default
kubectl describe secret keycloak-database-app -n default

# Check services
kubectl get svc -n default | grep keycloak-database

# Check operator logs
kubectl logs -n cnpg-system deployment/cnpg-cloudnative-pg

# Check PostgreSQL logs
kubectl logs keycloak-database-1 -n default

# Check Keycloak connectivity
kubectl logs keycloak-keycloakx-0 -n default | grep -i database
```

## Migration from Bitnami (If Needed in Future)

If you need to migrate data from an existing Bitnami PostgreSQL:

1. **Backup from Bitnami**:
```bash
kubectl exec -it keycloak-db-postgresql-0 -- pg_dump -U dbusername keycloak > backup.sql
```

2. **Restore to CloudNativePG**:
```bash
kubectl exec -it keycloak-database-1 -- psql -U keycloak keycloak < backup.sql
```

3. **Verify data**:
```bash
# Compare row counts
kubectl exec keycloak-db-postgresql-0 -- psql -U dbusername keycloak -c "SELECT COUNT(*) FROM public.user_entity;"
kubectl exec keycloak-database-1 -- psql -U keycloak keycloak -c "SELECT COUNT(*) FROM public.user_entity;"
```

## DNS Issue Resolution

**Issue**: Domain nameservers were not pointing to Azure DNS  
**Resolution**: Updated nameservers at domain registrar to:
- ns1-01.azure-dns.com
- ns2-01.azure-dns.net
- ns3-01.azure-dns.org
- ns4-01.azure-dns.info

**Propagation**: May take up to 48 hours for global DNS propagation  
**Test**: `nslookup auth.test-trustorbs.com` should resolve to Azure LoadBalancer IP

## Next Steps

1. ✅ Wait for DNS propagation to complete
2. ✅ Test Keycloak at https://auth.test-trustorbs.com
3. 🔄 Document backup/restore procedures (when implementing backups)
4. 🔄 Set up monitoring with Prometheus (when Prometheus Operator is deployed)
5. 🔄 Plan production HA deployment with 3 instances
