# Capability: Database Management

## ADDED Requirements

### Requirement: CloudNativePG Operator Deployment
The system SHALL deploy the CloudNativePG operator to manage PostgreSQL database clusters within the Kubernetes environment.

**Rationale**: Provides operator-based lifecycle management for PostgreSQL instances with automated backups, failover, and monitoring capabilities.

**Priority**: HIGH

#### Scenario: Deploy CloudNativePG operator successfully
- **GIVEN** a Kubernetes cluster with Helm installed
- **WHEN** the CloudNativePG operator Helm chart is deployed to the `cnpg-system` namespace
- **THEN** the operator pod SHALL be running and ready
- **AND** the CloudNativePG CRDs (Cluster, Backup, ScheduledBackup, Pooler) SHALL be registered in the cluster
- **AND** the operator SHALL be capable of managing PostgreSQL cluster resources

#### Scenario: Operator deployment fails due to missing prerequisites
- **GIVEN** a Kubernetes cluster that does not meet minimum version requirements (< 1.25)
- **WHEN** attempting to deploy the CloudNativePG operator
- **THEN** the deployment SHALL fail with a clear error message
- **AND** the error message SHALL indicate the minimum Kubernetes version required

### Requirement: PostgreSQL Cluster Deployment
The system SHALL deploy PostgreSQL clusters using CloudNativePG custom resources with configurable instance counts and resource allocations.

**Rationale**: Enables declarative PostgreSQL cluster management with support for both single-instance development and multi-instance HA production configurations.

**Priority**: HIGH

#### Scenario: Deploy single-instance PostgreSQL cluster for development
- **GIVEN** the CloudNativePG operator is running
- **WHEN** a Cluster manifest is applied with `instances: 1` and development resource specifications
- **THEN** a single PostgreSQL pod SHALL be created and reach ready state
- **AND** a PersistentVolumeClaim of 20Gi SHALL be provisioned
- **AND** the database "keycloak" SHALL be created with owner "keycloak"
- **AND** the pod SHALL pass readiness probes within 5 minutes

#### Scenario: Deploy multi-instance PostgreSQL cluster for production
- **GIVEN** the CloudNativePG operator is running
- **WHEN** a Cluster manifest is applied with `instances: 3` and production resource specifications
- **THEN** three PostgreSQL pods SHALL be created (1 primary, 2 replicas)
- **AND** all pods SHALL reach ready state within 10 minutes
- **AND** replication SHALL be established between primary and replicas
- **AND** pod anti-affinity SHALL ensure pods are scheduled on different nodes

#### Scenario: Cluster deployment fails due to insufficient storage
- **GIVEN** the Kubernetes cluster has insufficient storage quota
- **WHEN** a PostgreSQL cluster is deployed with storage request of 50Gi
- **THEN** the PVC creation SHALL fail
- **AND** the cluster status SHALL reflect "PendingPVC" condition
- **AND** the operator logs SHALL indicate the storage provisioning failure

### Requirement: Automatic Secret Generation
The system SHALL automatically generate Kubernetes secrets containing database credentials and connection information when a PostgreSQL cluster is created.

**Rationale**: Eliminates manual credential management and provides secure, auto-generated passwords with consistent secret structure.

**Priority**: HIGH

#### Scenario: Secret auto-generated on cluster creation
- **GIVEN** a CloudNativePG cluster named "keycloak-database" is deployed
- **WHEN** the cluster reaches ready state
- **THEN** a secret named "keycloak-database-app" SHALL be created automatically
- **AND** the secret SHALL contain keys: username, password, dbname, host, port, uri, jdbc-uri
- **AND** the password value SHALL be a cryptographically secure random string
- **AND** the host value SHALL be "keycloak-database-rw.default.svc.cluster.local"

#### Scenario: Application uses auto-generated secret for database connection
- **GIVEN** the secret "keycloak-database-app" has been created
- **WHEN** Keycloak pods reference this secret for database environment variables
- **THEN** Keycloak SHALL successfully connect to the PostgreSQL database
- **AND** authentication SHALL succeed using the auto-generated credentials
- **AND** Keycloak SHALL be able to create tables in the "keycloak" database

### Requirement: Service Endpoint Management
The system SHALL create multiple service endpoints for PostgreSQL clusters to support different connection patterns (read-write, read-only, any-instance).

**Rationale**: Enables routing of read-write traffic to primary instance and supports future read-replica load distribution for HA deployments.

**Priority**: HIGH

#### Scenario: Service endpoints created for single-instance cluster
- **GIVEN** a single-instance PostgreSQL cluster named "keycloak-database"
- **WHEN** the cluster is deployed
- **THEN** a service "keycloak-database-rw" SHALL be created pointing to the primary instance
- **AND** a service "keycloak-database-ro" SHALL be created (pointing to primary in single-instance)
- **AND** a service "keycloak-database-r" SHALL be created for any-instance access

#### Scenario: Service endpoints route correctly in HA cluster
- **GIVEN** a multi-instance PostgreSQL cluster with 1 primary and 2 replicas
- **WHEN** traffic is sent to "keycloak-database-rw" service
- **THEN** all traffic SHALL be routed to the primary instance
- **WHEN** traffic is sent to "keycloak-database-ro" service
- **THEN** traffic SHALL be load-balanced across replica instances only
- **AND** no read-only traffic SHALL reach the primary instance

#### Scenario: Service endpoint updates after failover
- **GIVEN** a multi-instance PostgreSQL cluster with automatic failover enabled
- **WHEN** the primary instance fails and a replica is promoted
- **THEN** the "keycloak-database-rw" service SHALL automatically update to point to the new primary
- **AND** the transition SHALL complete within 30 seconds
- **AND** existing connections SHALL be gracefully terminated

### Requirement: Keycloak Database Integration
The system SHALL configure Keycloak to connect to CloudNativePG-managed PostgreSQL databases using auto-generated secrets and service endpoints.

**Rationale**: Ensures Keycloak can successfully authenticate users and manage IAM data using the new database backend.

**Priority**: HIGH

#### Scenario: Keycloak connects to CloudNativePG database successfully
- **GIVEN** a CloudNativePG cluster "keycloak-database" is running and ready
- **AND** the secret "keycloak-database-app" has been created
- **WHEN** Keycloak is deployed with database configuration referencing the secret
- **THEN** Keycloak SHALL successfully connect to PostgreSQL
- **AND** Keycloak SHALL create all required tables (realm, user_entity, client, etc.)
- **AND** the Keycloak admin console SHALL be accessible
- **AND** Keycloak logs SHALL confirm successful database connection

#### Scenario: Keycloak handles database connection failure gracefully
- **GIVEN** CloudNativePG cluster is not running or not ready
- **WHEN** Keycloak attempts to start
- **THEN** Keycloak pods SHALL remain in CrashLoopBackOff state
- **AND** Keycloak logs SHALL clearly indicate database connection failure
- **AND** once the database becomes available, Keycloak SHALL automatically recover and start successfully

### Requirement: Data Persistence and Storage
The system SHALL provision persistent storage for PostgreSQL clusters with appropriate size and storage class configuration.

**Rationale**: Ensures database data survives pod restarts and provides adequate storage capacity for production workloads.

**Priority**: HIGH

#### Scenario: Persistent volume provisioned with correct size
- **GIVEN** a PostgreSQL cluster configuration specifying 20Gi storage
- **WHEN** the cluster is deployed
- **THEN** a PersistentVolumeClaim of exactly 20Gi SHALL be created
- **AND** the PVC SHALL be bound to a PersistentVolume within 2 minutes
- **AND** the storage class SHALL be "managed-csi" (Azure AKS default)

#### Scenario: Data persists across pod restarts
- **GIVEN** a PostgreSQL cluster with data written to the database
- **WHEN** the PostgreSQL pod is deleted (simulating restart)
- **THEN** a new pod SHALL be created automatically
- **AND** the new pod SHALL mount the same PVC
- **AND** all previously written data SHALL be accessible from the new pod

#### Scenario: Storage expansion for growing database
- **GIVEN** a PostgreSQL cluster with 20Gi storage that is 80% full
- **WHEN** the cluster storage size is updated to 50Gi
- **THEN** the PVC SHALL be expanded to 50Gi (if StorageClass supports expansion)
- **AND** the expansion SHALL complete without pod restart
- **AND** the additional storage SHALL be available to PostgreSQL

### Requirement: Terraform-Managed Infrastructure
The system SHALL deploy CloudNativePG resources using Terraform with proper dependency ordering and state management.

**Rationale**: Maintains infrastructure-as-code principles and ensures reproducible deployments across environments.

**Priority**: HIGH

#### Scenario: Terraform deploys CloudNativePG stack successfully
- **GIVEN** Terraform configuration includes CloudNativePG operator and cluster resources
- **WHEN** `terraform apply` is executed
- **THEN** the operator SHALL be deployed first
- **AND** the PostgreSQL cluster SHALL be deployed after operator is ready
- **AND** Keycloak SHALL be deployed after cluster is ready
- **AND** all resources SHALL be tracked in Terraform state

#### Scenario: Terraform handles cluster updates correctly
- **GIVEN** an existing PostgreSQL cluster managed by Terraform
- **WHEN** the cluster configuration is updated (e.g., instance count increased)
- **THEN** Terraform SHALL detect the change in plan
- **AND** Terraform apply SHALL update the cluster resource
- **AND** CloudNativePG operator SHALL handle the rolling update
- **AND** no data loss SHALL occur during the update

#### Scenario: Terraform destroy removes all resources cleanly
- **GIVEN** a full CloudNativePG stack deployed via Terraform
- **WHEN** `terraform destroy` is executed
- **THEN** all resources SHALL be removed in reverse dependency order
- **AND** PVCs SHALL be deleted
- **AND** no orphaned resources SHALL remain in the cluster

### Requirement: Migration from Bitnami PostgreSQL
The system SHALL provide clear procedures and tooling for migrating existing Bitnami PostgreSQL databases to CloudNativePG with data integrity validation.

**Rationale**: Enables safe transition from deprecated Bitnami charts to CloudNativePG without data loss.

**Priority**: HIGH

#### Scenario: Successful data migration from Bitnami to CloudNativePG
- **GIVEN** an existing Bitnami PostgreSQL database with Keycloak data
- **WHEN** migration procedure is executed (pg_dump and restore)
- **THEN** all data SHALL be exported from Bitnami database
- **AND** CloudNativePG cluster SHALL be created
- **AND** all data SHALL be imported into CloudNativePG database
- **AND** row counts for all tables SHALL match source database
- **AND** Keycloak SHALL connect to new database successfully
- **AND** all Keycloak functionality SHALL work correctly (authentication, realms, clients)

#### Scenario: Migration rollback on failure
- **GIVEN** migration from Bitnami to CloudNativePG is in progress
- **WHEN** data validation fails after restore
- **THEN** rollback procedure SHALL be executed
- **AND** Keycloak SHALL be reconfigured to point back to Bitnami database
- **AND** Bitnami database SHALL be scaled back up
- **AND** system SHALL return to pre-migration state
- **AND** no data loss SHALL occur

### Requirement: Monitoring and Observability
The system SHALL provide metrics and monitoring capabilities for PostgreSQL clusters using Prometheus integration.

**Rationale**: Enables proactive monitoring of database health, performance, and capacity for operational excellence.

**Priority**: MEDIUM

#### Scenario: Prometheus scrapes CloudNativePG metrics
- **GIVEN** a PostgreSQL cluster with monitoring enabled (`enablePodMonitor: true`)
- **AND** Prometheus is deployed in the cluster
- **WHEN** Prometheus scrapes the PostgreSQL pods
- **THEN** metrics SHALL be available in Prometheus
- **AND** metrics SHALL include: `cnpg_pg_database_size_bytes`, `cnpg_backends_total`, `cnpg_pg_replication_lag`
- **AND** metrics SHALL be updated every 30 seconds

#### Scenario: Monitor database storage usage
- **GIVEN** PostgreSQL cluster metrics are being collected
- **WHEN** database storage usage exceeds 80% of allocated capacity
- **THEN** the metric `cnpg_pg_database_size_bytes` SHALL reflect current usage
- **AND** operators SHALL be able to query this metric via Prometheus
- **AND** alerts CAN be configured based on this metric (if alerting is configured)

### Requirement: High Availability Configuration
The system SHALL support multi-instance PostgreSQL clusters with automated failover for production environments.

**Rationale**: Ensures database availability during primary instance failures and supports zero-downtime maintenance.

**Priority**: MEDIUM (future enhancement)

#### Scenario: Automatic failover on primary failure
- **GIVEN** a 3-instance PostgreSQL cluster (1 primary + 2 replicas) with `primaryUpdateStrategy: unsupervised`
- **WHEN** the primary instance pod is deleted or becomes unavailable
- **THEN** the operator SHALL detect the failure within 10 seconds
- **AND** one of the replicas SHALL be promoted to primary within 30 seconds
- **AND** the remaining replica SHALL switch replication to the new primary
- **AND** the "-rw" service SHALL update to point to the new primary
- **AND** Keycloak SHALL reconnect and resume operations within 1 minute

#### Scenario: Zero-downtime PostgreSQL version upgrade
- **GIVEN** a 3-instance PostgreSQL cluster with automated failover
- **WHEN** the PostgreSQL image version is updated in the cluster spec
- **THEN** the operator SHALL perform a rolling update
- **AND** one replica SHALL be updated at a time
- **AND** the primary SHALL be updated last
- **AND** no connection downtime SHALL occur for applications
- **AND** all instances SHALL be running the new version within 15 minutes

### Requirement: Backup and Recovery (Future)
The system SHALL support automated backups to Azure Blob Storage with configurable retention policies for production environments when backup configuration is enabled.

**Rationale**: Provides disaster recovery capability and point-in-time recovery for production databases. This is an optional feature that can be enabled when needed.

**Priority**: LOW (future enhancement)

#### Scenario: Automated daily backup to Azure Blob Storage
- **GIVEN** a PostgreSQL cluster with Barman backup configured
- **WHEN** the scheduled backup time is reached
- **THEN** a full backup SHALL be taken
- **AND** the backup SHALL be uploaded to Azure Blob Storage
- **AND** WAL (Write-Ahead Log) files SHALL be continuously archived
- **AND** backup status SHALL be reflected in the cluster status

#### Scenario: Point-in-time recovery from backup
- **GIVEN** automated backups have been running for 7 days
- **WHEN** a restore to a specific timestamp (e.g., 2 days ago) is requested
- **THEN** a new PostgreSQL cluster SHALL be created from the backup
- **AND** WAL files SHALL be replayed up to the specified timestamp
- **AND** the restored database SHALL contain data as it existed at that timestamp
- **AND** the restored cluster SHALL be fully functional

## REMOVED Requirements

### Requirement: Bitnami PostgreSQL Helm Chart Deployment
**Reason**: Bitnami charts have moved behind a paywall and are no longer accessible for automated deployments. This breaks CI/CD pipelines and prevents new environment provisioning.

**Migration Path**: Replace with CloudNativePG operator and cluster resources. Existing deployments must be migrated using pg_dump/restore procedures documented in migration runbook. The codecentric/keycloakx chart is compatible with both Bitnami and CloudNativePG PostgreSQL backends.

**Impact**: Requires configuration changes in Keycloak Helm values files to reference new secret names and service endpoints. Existing database data must be migrated to new CloudNativePG clusters.

## MODIFIED Requirements

None (this is a new capability replacing ad-hoc Bitnami deployment)
