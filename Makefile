ENV ?= dev
NAMESPACE := argocd
RELEASE := argocd

.PHONY: help install upgrade add-tenant lint local-cluster clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## First-time install (ENV=dev|staging|prod)
	@./scripts/install.sh $(ENV)

upgrade: ## Upgrade Argo CD (after editing platform/Chart.yaml version)
	@./scripts/upgrade.sh $(ENV)

add-tenant: ## Interactive tenant onboarding
	@./scripts/onboard-tenant.sh

lint: ## Validate all YAML and AppProject constraints
	@./scripts/validate.sh

local-cluster: ## Create a local kind cluster for testing
	@kind create cluster --name argocd-dev --wait 60s 2>/dev/null || echo "Cluster already exists"
	@kubectl cluster-info --context argocd-dev

clean: ## Delete local kind cluster
	@kind delete cluster --name argocd-dev

deps: ## Update Helm chart dependencies (only refresh argo-helm repo)
	@helm repo add argo-helm https://argoproj.github.io/argo-helm --force-update 2>/dev/null || true
	@helm repo update argo-helm
	@helm dependency update platform/ --skip-refresh
