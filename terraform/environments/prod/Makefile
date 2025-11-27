.PHONY: help init plan apply destroy clean

# Load environment variables from .env file
ifneq (,$(wildcard ../../.env))
    include ../../.env
    export
else
    $(error .env file not found. Copy .env.example to .env and configure your credentials)
endif

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform with backend configuration
	@echo "Initializing Terraform for prod environment..."
	terraform init -reconfigure

plan: ## Run terraform plan
	@echo "Planning Terraform changes for prod environment..."
	terraform plan -out=tfplan

apply: ## Apply Terraform changes (with confirmation)
	@echo "⚠️  WARNING: This will apply changes to PRODUCTION environment!"
	@read -p "Are you sure you want to proceed? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		terraform apply tfplan; \
	fi

apply-auto: ## Apply Terraform changes (no confirmation - USE WITH CAUTION)
	@echo "⚠️  Applying changes to PRODUCTION without confirmation..."
	terraform apply -auto-approve

destroy: ## Destroy all resources
	@echo "⚠️  WARNING: This will DESTROY all PRODUCTION resources!"
	@read -p "Type 'destroy-prod' to confirm: " -r; \
	echo; \
	if [[ $$REPLY == "destroy-prod" ]]; then \
		terraform destroy; \
	else \
		echo "Destruction cancelled."; \
	fi

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	terraform fmt -recursive
	terraform validate

kubeconfig: ## Get AKS credentials
	@echo "Fetching AKS credentials..."
	az aks get-credentials --resource-group rg-prod --name aks-prod --overwrite-existing

clean: ## Clean up temporary files
	@echo "Cleaning up temporary files..."
	rm -f tfplan
	rm -f .terraform.lock.hcl
	rm -rf .terraform

status: ## Show current deployment status
	@echo "Production Deployment Status:"
	@echo "============================="
	@terraform output -json 2>/dev/null | jq -r 'to_entries[] | "\(.key): \(.value.value)"' || echo "No outputs available. Run 'make init' and 'make apply' first."

logs-grafana: ## Show Grafana pod logs
	@echo "Fetching Grafana logs..."
	kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=100 -f

logs-prometheus: ## Show Prometheus logs
	@echo "Fetching Prometheus logs..."
	kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus --tail=100 -f

pods: ## Show all pods in monitoring namespace
	@echo "Monitoring Namespace Pods:"
	@kubectl get pods -n monitoring -o wide

services: ## Show all services in monitoring namespace
	@echo "Monitoring Namespace Services:"
	@kubectl get svc -n monitoring -o wide

certificates: ## Show all certificates
	@echo "Certificates:"
	@kubectl get certificates -A

port-forward-grafana: ## Port forward to Grafana
	@echo "Port forwarding to Grafana (http://localhost:3000)..."
	kubectl port-forward -n monitoring svc/grafana 3000:3000

port-forward-prometheus: ## Port forward to Prometheus
	@echo "Port forwarding to Prometheus (http://localhost:9090)..."
	kubectl port-forward -n monitoring svc/prometheus-server 9090:80
