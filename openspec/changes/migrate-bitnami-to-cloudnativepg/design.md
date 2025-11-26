# Technical Design: CloudNativePG Migration

## Architecture Overview

### Current Architecture (Bitnami PostgreSQL)
```
┌─────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                      │
│                                                               │
│  ┌──────────────┐          ┌─────────────────────────────┐  │
│  │   Keycloak   │          │   Bitnami PostgreSQL        │  │
│  │    Pods      │──────────│   StatefulSet (1 pod)       │  │
│  │              │          │                             │  │
│  │ Connection:  │          │   Service:                  │  │
│  │ - Host: keycloak-db-   │   keycloak-db-postgresql    │  │
│  │   postgresql           │   Port: 5432                │  │
│  │ - Secret: keycloak-db- │                             │  │
│  │   postgresql           │   PVC: 8-20Gi               │  │
│  └──────────────┘          └─────────────────────────────┘  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Target Architecture (CloudNativePG)
```
┌────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                          │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              CloudNativePG Operator (cnpg-system ns)         │   │
│  │  - Manages PostgreSQL clusters via CRDs                      │   │
│  │  - Automated failover, backups, monitoring                   │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────┐          ┌─────────────────────────────────┐     │
│  │   Keycloak   │          │   CloudNativePG Cluster         │     │
│  │    Pods      │──────────│   (Operator-managed)            │     │
│  │              │          │                                 │     │
│  │ Connection:  │          │   Dev: 1 instance               │     │
│  │ - Host: keycloak-      │   Prod: 3 instances (HA)        │     │
│  │   database-rw          │                                 │     │
│  │ - Secret: keycloak-    │   Services:                     │     │
│  │   database-app (auto)  │   - keycloak-database-rw (R/W)  │     │
│  │                        │   - keycloak-database-ro (RO)   │     │
│  │                        │   - keycloak-database-r  (Any)  │     │
│  │                        │                                 │     │
│  │                        │   PVCs: 20Gi per instance       │     │
│  └──────────────┘          └─────────────────────────────────┘     │
│                                                                      │
└────────────────────────────────────────────────────────────────────┘
```

## Design Decisions

### 1. Operator vs Direct Deployment
**Decision**: Use CloudNativePG Operator with CRD-based cluster management

**Rationale**:
- Operator provides automated lifecycle management (backups, failover, upgrades)
- CRD-based approach is declarative and fits Kubernetes patterns
- Better monitoring integration with Prometheus
- Simplified HA setup for future scaling
- Reduced operational overhead compared to manual StatefulSet management

**Alternatives Considered**:
- Direct PostgreSQL StatefulSet: More manual, lacks operator benefits
- Zalando Postgres Operator: Less mature, smaller community
- Continue with Bitnami: Not possible due to paywall

### 2. PostgreSQL Version
**Decision**: Use PostgreSQL 17.5 (latest stable)

**Rationale**:
- Keycloak supports PostgreSQL 12+ (confirmed compatible)
- Latest version provides best performance and security
- CloudNativePG images use official PostgreSQL containers
- Future-proof for long-term support

**Alternatives**:
- PostgreSQL 15.x: More conservative, but 17.5 is stable and tested

### 3. Development Configuration
**Decision**: Single-instance cluster for dev, HA-capable design for prod

**Rationale**:
- Dev environment needs minimal resources and cost
- Single instance sufficient for development/testing workloads
- Architecture supports scaling to 3+ instances without changes
- Allows testing migration path with minimal complexity

**Configuration**:
```yaml
instances: 1  # Dev
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
storage:
  size: 20Gi
  storageClass: managed-csi  # Azure AKS default
```

### 4. Production HA Configuration
**Decision**: 3-instance cluster with anti-affinity, automated backups

**Rationale**:
- 3 instances provide quorum for automated failover
- Anti-affinity ensures instances on different nodes
- Barman backup integration for point-in-time recovery
- Read replicas available for load distribution (future)

**Configuration**:
```yaml
instances: 3  # Production
primaryUpdateStrategy: unsupervised  # Auto-failover
affinity:
  podAntiAffinity: ...  # Different nodes
backup:
  barmanObjectStore:
    destinationPath: Azure Blob Storage
    retentionPolicy: "30d"
```

### 5. Secret Management
**Decision**: Use CloudNativePG auto-generated secrets

**Rationale**:
- CloudNativePG automatically creates `<cluster-name>-app` secret
- Secret contains all required fields (username, password, host, port, dbname, uri, jdbc-uri)
- Strong auto-generated passwords
- Compatible with Keycloak chart's `existingSecret` pattern
- No need to manage database credentials manually

**Secret Structure**:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-database-app  # Auto-created
data:
  username: <base64>   # keycloak
  password: <base64>   # Auto-generated secure password
  dbname: <base64>     # keycloak
  host: <base64>       # keycloak-database-rw
  port: <base64>       # 5432
  uri: <base64>        # Full connection URI
  jdbc-uri: <base64>   # JDBC format
```

### 6. Service Endpoints
**Decision**: Use `-rw` (read-write) service for Keycloak connections

**Rationale**:
- Keycloak requires write operations (user management, sessions)
- `-rw` service always points to primary instance
- Automatic failover handled by operator (updates service endpoint)
- `-ro` and `-r` services reserved for future read-only workloads

**Service Naming**:
- `keycloak-database-rw` - Primary (read-write)
- `keycloak-database-ro` - Replicas only (read-only, HA only)
- `keycloak-database-r` - Any instance (load balanced)

### 7. Storage Configuration
**Decision**: Use Azure managed-csi StorageClass with 20Gi base size

**Rationale**:
- Matches current Bitnami deployment patterns
- managed-csi is default AKS StorageClass
- 20Gi provides headroom for growth
- ReadWriteOnce sufficient for single-pod access per instance
- Production can use managed-csi-premium for better IOPS

**Storage Pattern**:
```yaml
storage:
  size: 20Gi
  storageClass: managed-csi  # Or managed-csi-premium for prod
```

### 8. Bootstrap Method
**Decision**: Use `initdb` bootstrap for new deployments

**Rationale**:
- Creates fresh database with correct locale and ownership
- Explicit database name and owner configuration
- Clean starting point for dev environment
- Migration from existing data uses separate restore procedure

**Bootstrap Configuration**:
```yaml
bootstrap:
  initdb:
    database: keycloak
    owner: keycloak
    localeCollate: 'en_US.UTF-8'
    localeCType: 'en_US.UTF-8'
```

### 9. Migration Strategy
**Decision**: pg_dump/restore for initial migration (dev environment)

**Rationale**:
- Dev environment is broken (Bitnami chart unavailable)
- Fresh deployment acceptable for dev
- Provides clean migration path for future prod migrations
- 5-30 minute downtime acceptable for maintenance window
- Simple, proven approach with clear rollback

**Migration Steps**:
1. Backup existing database (if recoverable)
2. Deploy CloudNativePG cluster
3. Restore from backup (if applicable)
4. Update Keycloak configuration
5. Verify and test

**Alternatives for Production** (future):
- Logical replication for zero-downtime migration
- Backup/restore via CloudNativePG bootstrap from backup

### 10. Monitoring Integration
**Decision**: Enable Prometheus PodMonitor from CloudNativePG

**Rationale**:
- Native Prometheus integration built into operator
- Provides PostgreSQL-specific metrics
- Integrates with existing Prometheus deployment
- Key metrics: replication lag, connections, storage usage

**Configuration**:
```yaml
monitoring:
  enablePodMonitor: true
```

**Key Metrics**:
- `cnpg_pg_replication_lag` - Replication lag in bytes
- `cnpg_pg_database_size_bytes` - Database size
- `cnpg_backends_total` - Active connections
- `cnpg_pg_stat_archiver_failed_count` - WAL archive failures

### 11. Backup Strategy (Production)
**Decision**: Barman integration with Azure Blob Storage, 30-day retention

**Rationale**:
- Barman is industry-standard PostgreSQL backup tool
- CloudNativePG has native Barman integration
- Azure Blob Storage cost-effective for backups
- 30-day retention meets compliance requirements
- Supports point-in-time recovery

**Backup Configuration**:
```yaml
backup:
  barmanObjectStore:
    destinationPath: "https://<account>.blob.core.windows.net/backups"
    azureCredentials:
      storageAccount: ...
      storageKey: ...
    wal:
      compression: gzip
      maxParallel: 2
  retentionPolicy: "30d"
```

### 12. Terraform Integration
**Decision**: Deploy operator via Helm, cluster via kubectl_manifest

**Rationale**:
- Operator is a standard Helm chart (easy updates)
- Cluster is a CRD - kubectl_manifest is appropriate
- Consistent with existing cert-manager pattern in codebase
- Separation of concerns: operator vs cluster lifecycle

**Terraform Resources**:
```hcl
# Operator
resource "helm_release" "cloudnativepg_operator" {
  name = "cnpg"
  chart = "cloudnative-pg/cloudnative-pg"
  namespace = "cnpg-system"
  create_namespace = true
}

# Cluster
resource "kubectl_manifest" "postgres_cluster" {
  yaml_body = file("${path.module}/database/postgres-cluster.yaml")
  depends_on = [helm_release.cloudnativepg_operator]
}
```

### 13. Rollback Strategy
**Decision**: Keep Bitnami deployment available (scaled down) for 7 days post-migration

**Rationale**:
- Provides safety net for production migration
- Quick rollback if critical issues discovered
- Allows data restoration if needed
- Minimal cost (PVC retained, no running pods)

**Rollback Procedure**:
1. Scale down CloudNativePG cluster (optional)
2. Restore Keycloak values to point to Bitnami
3. Scale up Bitnami StatefulSet
4. Restore database from pre-migration backup (if needed)

## Implementation Patterns

### Keycloak Configuration Update Pattern

**Before (Bitnami)**:
```yaml
database:
  vendor: postgres
  hostname: keycloak-db-postgresql
  port: 5432
  username: dbusername
  password: dbpassword
  database: keycloak
```

**After (CloudNativePG)**:
```yaml
extraEnv: |
  - name: KC_DB_URL_HOST
    valueFrom:
      secretKeyRef:
        name: keycloak-database-app
        key: host
  - name: KC_DB_URL_PORT
    valueFrom:
      secretKeyRef:
        name: keycloak-database-app
        key: port
  - name: KC_DB_URL_DATABASE
    valueFrom:
      secretKeyRef:
        name: keycloak-database-app
        key: dbname
  - name: KC_DB_USERNAME
    valueFrom:
      secretKeyRef:
        name: keycloak-database-app
        key: username

database:
  vendor: postgres
  existingSecret: keycloak-database-app
  existingSecretKey: password
```

### Terraform Dependency Chain

```
cloudnativepg_operator
         ↓
postgres_cluster
         ↓
certificate (existing)
         ↓
keycloak
```

## Security Considerations

### Secret Management
- Auto-generated passwords are cryptographically secure
- Secrets stored in Kubernetes with RBAC protection
- No plaintext credentials in configuration files
- Support for future secret rotation

### Network Security
- Database accessible only within cluster (ClusterIP)
- Optional NetworkPolicy to restrict access to Keycloak pods only
- TLS support for database connections (optional, recommended for prod)

### Encryption
- Encryption at rest via Azure Disk Encryption (AKS default)
- Encryption in transit via TLS (configurable)
- Backup encryption via Azure Blob Storage encryption

## Performance Considerations

### Resource Sizing
**Development**: Sized for low-traffic testing
- CPU: 250m request, 1000m limit
- Memory: 512Mi request, 1Gi limit
- Storage: 20Gi

**Production**: Sized for production workload with headroom
- CPU: 500m request, 2000m limit
- Memory: 1Gi request, 4Gi limit
- Storage: 50Gi+

### Connection Pooling
- Handled by Keycloak application layer
- PostgreSQL default max_connections: 100 (sufficient)
- Monitor connection usage via Prometheus metrics

### Storage Performance
- Development: managed-csi (standard SSD)
- Production: managed-csi-premium (premium SSD) for better IOPS

## Testing Strategy

### Unit Testing
- Terraform plan validation
- YAML syntax validation
- Secret structure validation

### Integration Testing
- Operator installation verification
- Cluster creation and readiness
- Secret auto-generation validation
- Keycloak database connectivity
- End-to-end authentication flow

### Migration Testing
- Dry run with test data
- Data integrity verification (table counts)
- Performance baseline comparison
- Rollback procedure validation

## Operational Runbook

### Day 1: Initial Deployment
1. Deploy CloudNativePG operator
2. Verify operator running: `kubectl get pods -n cnpg-system`
3. Deploy PostgreSQL cluster
4. Verify cluster ready: `kubectl get cluster -n default`
5. Verify secret created: `kubectl get secret keycloak-database-app`
6. Deploy Keycloak
7. Verify connectivity: Check Keycloak logs

### Day 2: Monitoring
- Check Prometheus metrics for database health
- Monitor replication lag (HA only)
- Verify backup jobs running (if configured)
- Check storage usage trends

### Common Operations
- **Scale instances**: Update `instances` in Cluster spec
- **Failover test**: Delete primary pod (operator handles failover)
- **Backup**: Automatic via Barman (if configured)
- **Restore**: Use CloudNativePG bootstrap from backup
- **View logs**: `kubectl logs -n default <pod-name>`

## Risk Mitigation

### Data Loss
- **Risk**: Migration failure or corruption
- **Mitigation**: Full backup before migration, validation scripts, rollback plan

### Extended Downtime
- **Risk**: Migration takes longer than expected
- **Mitigation**: Dry run practice, maintenance window, rollback trigger

### Performance Degradation
- **Risk**: CloudNativePG slower than Bitnami
- **Mitigation**: Baseline testing, resource sizing, monitoring

### Operator Bugs
- **Risk**: Operator software issues
- **Mitigation**: Use stable operator version (v1.24.1+), test thoroughly

## Future Enhancements

### Phase 2: High Availability
- Scale to 3 instances in production
- Test automated failover
- Implement read replica usage

### Phase 3: Advanced Backup
- Implement Azure Blob backup integration
- Configure point-in-time recovery
- Test disaster recovery procedures

### Phase 4: Monitoring & Alerting
- Create Grafana dashboards
- Set up alerts for critical metrics
- Integrate with incident management

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [Keycloak Database Configuration](https://www.keycloak.org/server/db)
- [codecentric/keycloakx Chart](https://github.com/codecentric/helm-charts/tree/master/charts/keycloakx)
- [Azure AKS Storage](https://learn.microsoft.com/en-us/azure/aks/concepts-storage)
