#!/usr/bin/env bash
# setup.sh — Full platform setup: cluster + ArgoCD + app-of-apps
set -euo pipefail

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[✓]${NC}     $*"; }
warn() { echo -e "${YELLOW}[!]${NC}     $*"; }
fail() { echo -e "${RED}[✗]${NC}     $*"; exit 1; }
step() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════${NC}\n"; }

CLUSTER_NAME="local-k8s-platform"
ARGOCD_CHART_VERSION="7.8.8"

# ──────────────────────────────────────────────────
# Step 0: Prerequisites
# ──────────────────────────────────────────────────
step "Step 0/6 — Checking prerequisites"
"$SCRIPT_DIR/prerequisites.sh"

# ──────────────────────────────────────────────────
# Step 1: Create k3d cluster
# ──────────────────────────────────────────────────
step "Step 1/6 — Creating k3d cluster"

if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    warn "Cluster '$CLUSTER_NAME' already exists"
    read -rp "Delete and recreate? [y/N] " RECREATE
    if [[ "${RECREATE,,}" == "y" ]]; then
        log "Deleting existing cluster..."
        k3d cluster delete "$CLUSTER_NAME"
    else
        log "Using existing cluster"
    fi
fi

if ! k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    log "Creating k3d cluster with config..."
    k3d cluster create --config "$REPO_ROOT/cluster/k3d-config.yaml"
    ok "Cluster created"
else
    ok "Cluster already running"
fi

# Wait for nodes to be ready
log "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s
ok "All nodes ready"

# ──────────────────────────────────────────────────
# Step 2: Install ArgoCD via Helm
# ──────────────────────────────────────────────────
step "Step 2/6 — Installing ArgoCD"

# Create namespace
kubectl apply -f "$REPO_ROOT/bootstrap/argocd/namespace.yaml"

# Add ArgoCD Helm repo
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

# Install ArgoCD
log "Installing ArgoCD via Helm (version ${ARGOCD_CHART_VERSION})..."
helm upgrade --install argo-cd argo/argo-cd \
    --namespace argocd \
    --version "$ARGOCD_CHART_VERSION" \
    --values "$REPO_ROOT/bootstrap/argocd/values.yaml" \
    --wait \
    --timeout 5m

ok "ArgoCD installed"

# ──────────────────────────────────────────────────
# Step 3: Wait for ArgoCD to be ready
# ──────────────────────────────────────────────────
step "Step 3/6 — Waiting for ArgoCD to be ready"

log "Waiting for ArgoCD server deployment..."
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=180s
ok "ArgoCD server is ready"

# ──────────────────────────────────────────────────
# Step 4: Build & import argo-marketplace image
# ──────────────────────────────────────────────────
step "Step 4/7 — Building ArgoCD Marketplace UI"

ARGO_MARKETPLACE_DIR="$HOME/argo-marketplace"
if [ -d "$ARGO_MARKETPLACE_DIR" ]; then
    log "Building argo-marketplace Docker image..."
    docker build -t argo-marketplace:latest "$ARGO_MARKETPLACE_DIR" --quiet
    ok "Docker image built"

    log "Importing image into k3d cluster..."
    k3d image import argo-marketplace:latest -c local-k8s-platform
    ok "Image imported into cluster"
else
    warn "argo-marketplace repo not found at $ARGO_MARKETPLACE_DIR"
    warn "Skipping image build — clone it from https://github.com/Karthik-Chowdary/argo-marketplace"
    warn "The argo-marketplace app will be in CrashLoopBackOff until the image is available"
fi

# ──────────────────────────────────────────────────
# Step 5: Apply app-of-apps
# ──────────────────────────────────────────────────
step "Step 5/7 — Deploying app-of-apps"

log "Applying root Application manifest..."
kubectl apply -f "$REPO_ROOT/bootstrap/app-of-apps.yaml"
ok "App-of-apps deployed — ArgoCD will now sync all applications"

# ──────────────────────────────────────────────────
# Step 5: Wait for core apps
# ──────────────────────────────────────────────────
step "Step 6/7 — Waiting for applications to sync"

log "Waiting for ingress-nginx namespace to appear..."
for i in $(seq 1 60); do
    if kubectl get namespace ingress-nginx &>/dev/null; then
        ok "ingress-nginx namespace created"
        break
    fi
    sleep 5
    echo -n "."
done

log "Waiting for ingress-nginx controller..."
for i in $(seq 1 60); do
    if kubectl get deployment -n ingress-nginx ingress-nginx-controller &>/dev/null; then
        kubectl rollout status deployment/ingress-nginx-controller -n ingress-nginx --timeout=180s && break
    fi
    sleep 5
    echo -n "."
done
ok "Ingress controller ready"

log "Waiting for monitoring namespace..."
for i in $(seq 1 60); do
    if kubectl get namespace monitoring &>/dev/null; then
        ok "monitoring namespace created"
        break
    fi
    sleep 5
    echo -n "."
done

log "Giving ArgoCD time to sync remaining apps (60s)..."
sleep 60

# ──────────────────────────────────────────────────
# Step 6: Summary
# ──────────────────────────────────────────────────
step "Step 7/7 — Setup Complete! 🎉"

ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "run: make argocd-password")

echo -e "${GREEN}${BOLD}"
echo "  ┌────────────────────────────────────────────────────────────┐"
echo "  │                  🚀 Platform is Ready!                     │"
echo "  ├────────────────────────────────────────────────────────────┤"
echo "  │                                                            │"
echo "  │  Service          URL                        Credentials   │"
echo "  │  ───────          ───                        ───────────   │"
echo "  │  ArgoCD           http://argocd.localhost     admin/$ARGOCD_PASSWORD"
echo "  │  Grafana          http://grafana.localhost    admin/admin   │"
echo "  │  Prometheus       http://prometheus.localhost    —          │"
echo "  │  Alertmanager     http://alertmanager.localhost  —          │"
echo "  │  Podinfo          http://podinfo.localhost       —          │"
echo "  │  Echoserver       http://echoserver.localhost    —          │"
echo "  │  Marketplace      http://marketplace.localhost   —          │"
echo "  │                                                            │"
echo "  ├────────────────────────────────────────────────────────────┤"
echo "  │  Useful commands:                                          │"
echo "  │    make status          — Check platform status            │"
echo "  │    make argocd-password — Get ArgoCD password              │"
echo "  │    make argocd-ui       — Port-forward ArgoCD              │"
echo "  │    make grafana-ui      — Port-forward Grafana             │"
echo "  │    make down            — Tear everything down             │"
echo "  └────────────────────────────────────────────────────────────┘"
echo -e "${NC}"

echo -e "${YELLOW}💡 Tip: If *.localhost doesn't resolve, use 'make argocd-ui' for port-forwarding.${NC}"
echo ""
