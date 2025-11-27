# Monitoring Stack Specification

This specification defines the requirements for the monitoring and observability stack in TrustOrbs, including metrics collection, visualization, and alerting capabilities for Keycloak identity management deployments.

## ADDED Requirements

### Requirement: Grafana Dashboard Visualization
The system SHALL provide a Grafana instance for visualizing Keycloak metrics and system health through interactive dashboards.

#### Scenario: Grafana successfully deploys with Prometheus integration
- **GIVEN** a Kubernetes cluster with Prometheus deployed in the `monitoring` namespace
- **WHEN** Terraform applies the monitoring stack configuration
- **THEN** Grafana deploys successfully in the `monitoring` namespace
- **AND** Grafana automatically configures Prometheus as a data source
- **AND** the Prometheus data source URL is `http://prometheus-server.monitoring.svc.cluster.local`
- **AND** Grafana is accessible and responsive

#### Scenario: Pre-configured Keycloak dashboard loads automatically
- **GIVEN** Grafana is deployed and running
- **WHEN** a user accesses the Grafana web interface
- **THEN** the Keycloak metrics dashboard is pre-loaded and available
- **AND** the dashboard displays all Keycloak base metrics (JVM, CPU, memory, threads)
- **AND** the dashboard displays Keycloak vendor metrics (database connections, cache statistics)
- **AND** all dashboard panels successfully query Prometheus and display data

#### Scenario: Dashboard visualizes live Keycloak metrics
- **GIVEN** Keycloak is running and exposing metrics on port 9000
- **AND** Prometheus is scraping Keycloak metrics
- **AND** Grafana is configured with the Keycloak dashboard
- **WHEN** a user views the dashboard
- **THEN** real-time metrics are displayed including:
- **AND** Available processors and system CPU load
- **AND** Process CPU usage and load average
- **AND** JVM heap memory (committed, max, used)
- **AND** Thread counts (active, daemon, peak)
- **AND** Database connection pool statistics
- **AND** Garbage collection metrics
- **AND** All graphs update automatically based on the configured refresh interval

### Requirement: External Grafana Accessibility
The system SHALL expose Grafana externally via Azure LoadBalancer with a predictable DNS name for easy access by operations teams.

#### Scenario: Grafana accessible via LoadBalancer
- **GIVEN** Grafana is deployed in the cluster
- **WHEN** Terraform creates the Grafana LoadBalancer service
- **THEN** Azure assigns a public IP address to the LoadBalancer
- **AND** the LoadBalancer forwards traffic to Grafana pods on port 3000
- **AND** the LoadBalancer is annotated with a predictable Azure DNS label
- **AND** users can access Grafana via `http://<loadbalancer-dns>:3000`

#### Scenario: DNS CNAME record created for Grafana
- **GIVEN** the Grafana LoadBalancer service is created
- **WHEN** Terraform applies the DNS configuration
- **THEN** a CNAME record is created in the Azure DNS zone
- **AND** the CNAME points to `grafana-${deployment_prefix}.eastus.cloudapp.azure.com`
- **AND** the record name follows the pattern `grafana-${deployment_prefix}`
- **AND** users can access Grafana via `http://grafana-${deployment_prefix}.${dns_zone_name}:3000`

#### Scenario: Multi-tenant Grafana isolation
- **GIVEN** multiple customer deployments exist
- **WHEN** each deployment creates its own Grafana instance
- **THEN** each Grafana has a unique DNS name based on the deployment prefix
- **AND** each Grafana only displays metrics from its own Keycloak instance
- **AND** Grafana instances are isolated and cannot access each other's data

### Requirement: Grafana Authentication and Security
The system SHALL secure Grafana with basic username/password authentication and support configurable credentials per deployment environment.

#### Scenario: Admin credentials configured from Terraform variables
- **GIVEN** Grafana deployment configuration includes admin credentials
- **WHEN** Terraform applies the Helm release
- **THEN** Grafana admin username is set from `grafana_admin_username` variable
- **AND** Grafana admin password is set from `grafana_admin_password` variable
- **AND** credentials are stored securely in Kubernetes secrets
- **AND** credentials are not exposed in Terraform state as plaintext

#### Scenario: Successful authentication required for access
- **GIVEN** Grafana is accessible via LoadBalancer
- **WHEN** a user attempts to access Grafana without authentication
- **THEN** Grafana redirects to the login page
- **AND** anonymous access is disabled by default
- **AND** users must provide valid username and password

#### Scenario: Basic authentication used (no Azure AD)
- **GIVEN** Grafana is configured for authentication
- **WHEN** a user logs in
- **THEN** basic username/password authentication is used
- **AND** no Azure AD integration is required
- **AND** authentication method can be upgraded to Azure AD in future

#### Scenario: Admin user can manage dashboards and data sources
- **GIVEN** a user authenticates with admin credentials
- **WHEN** the user accesses the Grafana interface
- **THEN** the user can view all dashboards
- **AND** the user can create, edit, and delete dashboards
- **AND** the user can manage data sources
- **AND** the user can create additional users and configure permissions

### Requirement: External Access SSL/TLS Configuration
The system SHALL use cert-manager to provision TLS certificates for HTTPS access to Grafana.

#### Scenario: Certificate resource created for Grafana subdomain
- **GIVEN** cert-manager is deployed with a ClusterIssuer configured
- **WHEN** Terraform applies the Grafana certificate configuration
- **THEN** a Certificate resource is created for the Grafana subdomain
- **AND** the certificate DNS name is `grafana-${deployment_prefix}.${dns_zone_name}`
- **AND** the certificate references the existing ClusterIssuer
- **AND** cert-manager automatically provisions the certificate from Let's Encrypt

#### Scenario: Certificate successfully issued and stored
- **GIVEN** a Certificate resource exists for Grafana
- **WHEN** cert-manager processes the certificate request
- **THEN** cert-manager creates a TLS secret with the certificate and private key
- **AND** the secret is created in the `monitoring` namespace
- **AND** the certificate is valid and trusted by browsers
- **AND** certificate auto-renewal is configured before expiration

#### Scenario: Grafana LoadBalancer configured with TLS
- **GIVEN** the TLS certificate secret exists
- **WHEN** the Grafana LoadBalancer service is configured
- **THEN** the LoadBalancer terminates TLS using the certificate secret
- **AND** HTTPS traffic on port 443 is forwarded to Grafana
- **AND** HTTP to HTTPS redirect is configured (optional but recommended)

#### Scenario: HTTPS access works with trusted certificate
- **GIVEN** Grafana is deployed with TLS certificate
- **WHEN** a user accesses `https://grafana-${deployment_prefix}.${dns_zone_name}`
- **THEN** the connection is encrypted with TLS
- **AND** browsers show a valid certificate (no warnings)
- **AND** the certificate is issued by Let's Encrypt
- **AND** admin credentials are transmitted securely over HTTPS

### Requirement: Persistent Storage for Grafana Configuration
The system SHALL configure persistent storage for Grafana to retain dashboard customizations, data sources, and user configurations across pod restarts.

#### Scenario: Persistent volume provisioned for Grafana
- **GIVEN** Grafana Helm chart deployment with persistent storage enabled
- **WHEN** Terraform applies the configuration
- **THEN** a PersistentVolumeClaim (PVC) is created in the `monitoring` namespace
- **AND** the PVC uses Azure Disk storage class
- **AND** the PVC size is at least 10Gi
- **AND** the PVC is mounted to Grafana pods at `/var/lib/grafana`

#### Scenario: Dashboard changes persist after pod restart
- **GIVEN** a user customizes the Keycloak dashboard in Grafana
- **AND** saves the changes
- **WHEN** the Grafana pod is restarted or rescheduled
- **THEN** the customized dashboard is retained
- **AND** all custom configurations are preserved

#### Scenario: Data source configurations persist across restarts
- **GIVEN** additional data sources are configured in Grafana
- **WHEN** the Grafana pod restarts
- **THEN** all configured data sources remain available
- **AND** data source credentials are retained securely

### Requirement: Automated Dashboard Provisioning
The system SHALL automatically provision the Keycloak metrics dashboard during Grafana deployment without requiring manual import steps, with dashboards configured as editable.

#### Scenario: Dashboard ConfigMap created with dashboard JSON
- **GIVEN** the keycloak-dashboard.json file exists in the terraform module
- **WHEN** Terraform applies the Grafana configuration
- **THEN** a Kubernetes ConfigMap is created containing the dashboard JSON
- **AND** the ConfigMap is labeled for Grafana dashboard provisioning
- **AND** the ConfigMap is mounted to Grafana's provisioning directory

#### Scenario: Dashboard automatically loads on Grafana startup
- **GIVEN** the dashboard ConfigMap exists and is mounted
- **WHEN** Grafana starts or restarts
- **THEN** Grafana automatically discovers the dashboard from the provisioning directory
- **AND** the dashboard is imported without manual intervention
- **AND** the dashboard appears in the Grafana dashboard list

#### Scenario: Dashboards are editable in Grafana UI
- **GIVEN** a dashboard is provisioned from ConfigMap
- **WHEN** a user opens the dashboard in Grafana
- **THEN** the dashboard provisioning configuration sets `editable: true`
- **AND** the dashboard provisioning sets `disableDeletion: false`
- **AND** users can modify the dashboard in the UI
- **AND** users can save changes to the dashboard
- **AND** UI changes persist in Grafana's persistent storage

#### Scenario: Dashboard template maintained in version control
- **GIVEN** the dashboard template is stored in Git
- **WHEN** users make changes in Grafana UI
- **THEN** documentation provides process to export modified dashboards
- **AND** exported dashboards can be saved back to Git repository
- **AND** ConfigMap can be updated with new dashboard version
- **AND** Helm upgrade applies updated dashboard template

#### Scenario: Dashboard data source UID resolves correctly
- **GIVEN** the dashboard references a Prometheus data source
- **WHEN** the dashboard is provisioned
- **THEN** Grafana resolves the data source reference to the configured Prometheus instance
- **AND** all dashboard panels successfully query metrics
- **AND** no data source configuration errors are displayed

### Requirement: Monitoring Stack Deployment Order
The system SHALL deploy monitoring components in the correct dependency order to ensure successful initialization.

#### Scenario: Prometheus deployed before Grafana
- **GIVEN** a fresh Terraform deployment
- **WHEN** Terraform plans the resource creation order
- **THEN** Prometheus Helm release is created before Grafana Helm release
- **AND** Grafana waits for Prometheus to be ready before configuration

#### Scenario: Grafana waits for LoadBalancer before DNS
- **GIVEN** Grafana LoadBalancer service is being created
- **WHEN** Terraform creates the DNS CNAME record
- **THEN** the DNS record creation waits for LoadBalancer public IP assignment
- **AND** the CNAME points to the correct LoadBalancer FQDN

#### Scenario: All monitoring components healthy after deployment
- **GIVEN** Terraform apply completes successfully
- **WHEN** checking the monitoring namespace
- **THEN** Prometheus pods are running and healthy
- **AND** Grafana pods are running and healthy
- **AND** both services are accessible
- **AND** Grafana can successfully query Prometheus

### Requirement: Terraform Output for Grafana Access
The system SHALL provide Terraform outputs with the Grafana URL for easy access and documentation.

#### Scenario: Grafana URL output generated
- **GIVEN** Grafana deployment is complete
- **WHEN** Terraform apply finishes
- **THEN** an output named `grafana_url` is displayed
- **AND** the output value is `http://grafana-${deployment_prefix}.${dns_zone_name}:3000`
- **AND** the URL is immediately accessible via the LoadBalancer

#### Scenario: Multiple URLs displayed for all services
- **GIVEN** the deployment includes Keycloak and Grafana
- **WHEN** viewing Terraform outputs
- **THEN** both `keycloak_url` and `grafana_url` outputs are shown
- **AND** each URL is correctly formatted for external access
- **AND** documentation references these outputs for accessing services
