.PHONY: help up down status prerequisites argocd-password argocd-ui grafana-ui add-app logs

SHELL := /bin/bash
CLUSTER_NAME := local-k8s-platform

# Colors
GREEN  := \033[0;32m
YELLOW := \033[0;33m
CYAN   := \033[0;36m
RED    := \033[0;31m
NC     := \033[0m

help: ## Show this help
	@echo ""
	@echo "$(CYAN)🚀 Local K8s Platform$(NC)"
	@echo "$(CYAN)=====================$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

up: ## 🚀 Full platform setup (cluster + all apps)
	@./scripts/setup.sh

down: ## 🗑️  Tear everything down
	@./scripts/teardown.sh

status: ## 📊 Show platform status, URLs, and ArgoCD sync
	@echo ""
	@echo "$(CYAN)═══════════════════════════════════════$(NC)"
	@echo "$(CYAN)  📊 Platform Status$(NC)"
	@echo "$(CYAN)═══════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(YELLOW)🔗 Cluster:$(NC)"
	@k3d cluster list 2>/dev/null || echo "  No cluster found"
	@echo ""
	@echo "$(YELLOW)🌐 URLs:$(NC)"
	@echo "  ArgoCD:       http://argocd.localhost"
	@echo "  Grafana:      http://grafana.localhost"
	@echo "  Prometheus:   http://prometheus.localhost"
	@echo "  Alertmanager: http://alertmanager.localhost"
	@echo "  Podinfo:      http://podinfo.localhost"
	@echo "  Echoserver:   http://echoserver.localhost"
	@echo ""
	@echo "$(YELLOW)📦 Pods:$(NC)"
	@kubectl get pods -A --no-headers 2>/dev/null | awk '{printf "  %-30s %-40s %s\n", $$1, $$2, $$4}' || echo "  Cannot reach cluster"
	@echo ""
	@echo "$(YELLOW)🔄 ArgoCD Applications:$(NC)"
	@kubectl get applications -n argocd 2>/dev/null || echo "  ArgoCD not available"
	@echo ""

prerequisites: ## 🔍 Check and install prerequisites
	@./scripts/prerequisites.sh

argocd-password: ## 🔑 Get ArgoCD admin password
	@echo ""
	@echo "$(CYAN)ArgoCD Admin Password:$(NC)"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d && echo "" || echo "$(RED)Could not retrieve password. Is ArgoCD running?$(NC)"
	@echo ""

argocd-ui: ## 🖥️  Port-forward ArgoCD UI to localhost:8080
	@echo "$(GREEN)ArgoCD UI available at: http://localhost:8080$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@kubectl port-forward svc/argo-cd-argocd-server -n argocd 8080:443

grafana-ui: ## 📊 Port-forward Grafana to localhost:3000
	@echo "$(GREEN)Grafana available at: http://localhost:3000$(NC)"
	@echo "$(YELLOW)Credentials: admin / admin$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

prometheus-ui: ## 📈 Port-forward Prometheus to localhost:9090
	@echo "$(GREEN)Prometheus available at: http://localhost:9090$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to stop$(NC)"
	@kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090

add-app: ## ➕ Instructions for adding a new app
	@echo ""
	@echo "$(CYAN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(CYAN)  ➕ Adding a New Application$(NC)"
	@echo "$(CYAN)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(GREEN)1.$(NC) Create an ArgoCD Application manifest in $(YELLOW)apps/$(NC)"
	@echo "$(GREEN)2.$(NC) (Optional) Add Helm values in $(YELLOW)helm-values/$(NC)"
	@echo "$(GREEN)3.$(NC) Commit and push"
	@echo "$(GREEN)4.$(NC) ArgoCD picks it up automatically!"
	@echo ""
	@echo "$(YELLOW)Example:$(NC)"
	@echo ""
	@echo "  cat > apps/my-app.yaml << 'EOF'"
	@echo "  apiVersion: argoproj.io/v1alpha1"
	@echo "  kind: Application"
	@echo "  metadata:"
	@echo "    name: my-app"
	@echo "    namespace: argocd"
	@echo "    finalizers:"
	@echo "      - resources-finalizer.argocd.argoproj.io"
	@echo "  spec:"
	@echo "    project: default"
	@echo "    source:"
	@echo "      repoURL: https://charts.example.com"
	@echo "      targetRevision: \"1.0.0\""
	@echo "      chart: my-app"
	@echo "    destination:"
	@echo "      server: https://kubernetes.default.svc"
	@echo "      namespace: my-app"
	@echo "    syncPolicy:"
	@echo "      automated:"
	@echo "        prune: true"
	@echo "        selfHeal: true"
	@echo "      syncOptions:"
	@echo "        - CreateNamespace=true"
	@echo "  EOF"
	@echo ""
	@echo "📖 Full guide: docs/ADDING_APPS.md"
	@echo ""

logs: ## 📜 Tail important pod logs
	@echo "$(CYAN)Tailing ArgoCD server logs...$(NC)"
	@echo "$(YELLOW)(Press Ctrl+C to stop)$(NC)"
	@kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 -f 2>/dev/null || echo "$(RED)ArgoCD not running$(NC)"
