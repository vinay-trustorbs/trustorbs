.PHONY: help init plan apply destroy clean workspace-new workspace-select workspace-list

# Load environment variables from .env file
ifneq (,$(wildcard ../../.env))
    include ../../.env
    export
else
    $(error .env file not found. Copy .env.example to .env and configure your credentials)
endif

# Customer name (override with: make apply CUSTOMER=customer1)
CUSTOMER ?= customer1

help: ## Show this help message
	@echo 'Usage: make [target] CUSTOMER=<customer_name>'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ''
	@echo 'Examples:'
	@echo '  make deploy CUSTOMER=acmecorp'
	@echo '  make destroy CUSTOMER=acmecorp'

init: ## Initialize Terraform with backend configuration
	@echo "Initializing Terraform for customer deployments..."
	terraform init -backend-config=backend.tfvars -reconfigure

workspace-new: ## Create a new workspace for a customer
	@echo "Creating workspace for customer: $(CUSTOMER)..."
	terraform workspace new $(CUSTOMER) || true

workspace-select: ## Select an existing workspace
	@echo "Selecting workspace: $(CUSTOMER)..."
	terraform workspace select $(CUSTOMER)

workspace-list: ## List all workspaces
	@echo "Available customer workspaces:"
	terraform workspace list

plan: workspace-select ## Run terraform plan for customer
	@echo "Planning Terraform changes for customer: $(CUSTOMER)..."
	terraform plan -out=tfplan

apply: workspace-select ## Apply Terraform changes for customer
	@echo "Applying Terraform changes for customer: $(CUSTOMER)..."
	terraform apply -auto-approve

apply-plan: workspace-select ## Apply the saved plan
	@echo "Applying saved Terraform plan for customer: $(CUSTOMER)..."
	terraform apply tfplan

destroy: workspace-select ## Destroy customer resources
	@echo "⚠️  WARNING: This will destroy all resources for customer: $(CUSTOMER)!"
	@read -p "Type 'destroy-$(CUSTOMER)' to confirm: " -r; \
	echo; \
	if [[ $$REPLY == "destroy-$(CUSTOMER)" ]]; then \
		terraform destroy -auto-approve; \
	else \
		echo "Destruction cancelled."; \
	fi

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	terraform fmt -recursive
	terraform validate

kubeconfig: workspace-select ## Get AKS credentials for customer
	@echo "Fetching AKS credentials for customer: $(CUSTOMER)..."
	@CLUSTER_NAME=$$(terraform output -raw aks_cluster_name 2>/dev/null || echo "aks-$(CUSTOMER)"); \
	RG_NAME=$$(terraform output -raw deployment_prefix 2>/dev/null || echo "$(CUSTOMER)"); \
	az aks get-credentials --resource-group rg-$$RG_NAME --name $$CLUSTER_NAME --overwrite-existing

clean: ## Clean up temporary files
	@echo "Cleaning up temporary files..."
	rm -f tfplan
	rm -f .terraform.lock.hcl
	rm -rf .terraform

status: workspace-select ## Show current deployment status
	@echo "Customer Deployment Status ($(CUSTOMER)):"
	@echo "=========================================="
	@terraform output -json 2>/dev/null | jq -r 'to_entries[] | "\(.key): \(.value.value)"' || echo "No outputs available. Run 'make deploy CUSTOMER=$(CUSTOMER)' first."

logs-grafana: kubeconfig ## Show Grafana pod logs
	@echo "Fetching Grafana logs for customer: $(CUSTOMER)..."
	kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100 -f

logs-prometheus: kubeconfig ## Show Prometheus logs
	@echo "Fetching Prometheus logs for customer: $(CUSTOMER)..."
	kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100 -f

pods: kubeconfig ## Show all pods in monitoring namespace
	@echo "Monitoring Namespace Pods ($(CUSTOMER)):"
	@kubectl get pods -n monitoring -o wide

services: kubeconfig ## Show all services in monitoring namespace
	@echo "Monitoring Namespace Services ($(CUSTOMER)):"
	@kubectl get svc -n monitoring -o wide

certificates: kubeconfig ## Show all certificates
	@echo "Certificates ($(CUSTOMER)):"
	@kubectl get certificates -A

port-forward-grafana: kubeconfig ## Port forward to Grafana
	@echo "Port forwarding to Grafana for $(CUSTOMER) (http://localhost:3000)..."
	kubectl port-forward -n monitoring svc/grafana 3000:3000

port-forward-prometheus: kubeconfig ## Port forward to Prometheus
	@echo "Port forwarding to Prometheus for $(CUSTOMER) (http://localhost:9090)..."
	kubectl port-forward -n monitoring svc/prometheus-server 9090:80

# Quick deployment workflow
deploy: init workspace-new validate plan apply kubeconfig status ## Complete deployment workflow for new customer

# Re-deploy existing customer
redeploy: init workspace-select validate plan apply kubeconfig status ## Re-deploy existing customer
