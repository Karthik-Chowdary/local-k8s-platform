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
ARGO_MARKETPLACE_REPO="https://github.com/Karthik-Chowdary/argo-marketplace.git"
ARGO_MARKETPLACE_DIR="$HOME/argo-marketplace"

# ──────────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────────
WITH_MARKETPLACE=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --with-marketplace    Include ArgoCD Marketplace UI (browse & deploy Helm charts)"
    echo "  --help                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Core platform only"
    echo "  $0 --with-marketplace   # Core platform + Marketplace UI"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-marketplace)
            WITH_MARKETPLACE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            warn "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Calculate total steps
if $WITH_MARKETPLACE; then
    TOTAL_STEPS=7
else
    TOTAL_STEPS=6
fi
STEP=0

next_step() {
    STEP=$((STEP + 1))
    step "Step ${STEP}/${TOTAL_STEPS} — $1"
}

# ──────────────────────────────────────────────────
# Step: Prerequisites
# ──────────────────────────────────────────────────
next_step "Checking prerequisites"
"$SCRIPT_DIR/prerequisites.sh"

# ──────────────────────────────────────────────────
# Step: Create k3d cluster
# ──────────────────────────────────────────────────
next_step "Creating k3d cluster"

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
# Step: Install ArgoCD via Helm
# ──────────────────────────────────────────────────
next_step "Installing ArgoCD"

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
# Step: Wait for ArgoCD to be ready
# ──────────────────────────────────────────────────
next_step "Waiting for ArgoCD to be ready"

log "Waiting for ArgoCD server deployment..."
kubectl rollout status deployment/argo-cd-argocd-server -n argocd --timeout=180s
ok "ArgoCD server is ready"

# ──────────────────────────────────────────────────
# Step: Build & import argo-marketplace (conditional)
# ──────────────────────────────────────────────────
if $WITH_MARKETPLACE; then
    next_step "Setting up ArgoCD Marketplace UI"

    # Clone if not present
    if [ ! -d "$ARGO_MARKETPLACE_DIR" ]; then
        log "Cloning argo-marketplace..."
        git clone "$ARGO_MARKETPLACE_REPO" "$ARGO_MARKETPLACE_DIR"
        ok "Repository cloned to $ARGO_MARKETPLACE_DIR"
    else
        log "argo-marketplace repo found at $ARGO_MARKETPLACE_DIR"
        log "Pulling latest changes..."
        (cd "$ARGO_MARKETPLACE_DIR" && git pull --ff-only 2>/dev/null) || warn "Could not pull latest (may have local changes)"
    fi

    # Build Docker image
    log "Building argo-marketplace Docker image (this may take a minute)..."
    docker build -t argo-marketplace:latest "$ARGO_MARKETPLACE_DIR" --quiet
    ok "Docker image built"

    # Import into k3d
    log "Importing image into k3d cluster..."
    k3d image import argo-marketplace:latest -c "$CLUSTER_NAME"
    ok "Image imported into cluster"

    # Copy the ArgoCD app definition into apps/ so app-of-apps picks it up
    if [ ! -f "$REPO_ROOT/apps/argo-marketplace.yaml" ]; then
        log "Adding argo-marketplace to apps/ directory..."
        cp "$REPO_ROOT/optional/argo-marketplace-app.yaml" "$REPO_ROOT/apps/argo-marketplace.yaml"
        (cd "$REPO_ROOT" && git add apps/argo-marketplace.yaml && git commit -m "feat: enable argo-marketplace (via --with-marketplace)" --no-verify 2>/dev/null && git push origin main 2>/dev/null) || warn "Could not auto-commit (manual push may be needed)"
        ok "argo-marketplace app added to GitOps"
    else
        ok "argo-marketplace app already in apps/"
    fi
fi

# ──────────────────────────────────────────────────
# Step: Apply app-of-apps
# ──────────────────────────────────────────────────
next_step "Deploying app-of-apps"

log "Applying root Application manifest..."
kubectl apply -f "$REPO_ROOT/bootstrap/app-of-apps.yaml"
ok "App-of-apps deployed — ArgoCD will now sync all applications"

# ──────────────────────────────────────────────────
# Step: Wait for core apps
# ──────────────────────────────────────────────────
next_step "Waiting for applications to sync"

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

if $WITH_MARKETPLACE; then
    log "Waiting for argo-marketplace to be ready..."
    for i in $(seq 1 30); do
        if kubectl get deployment -n argo-marketplace argo-marketplace &>/dev/null; then
            kubectl rollout status deployment/argo-marketplace -n argo-marketplace --timeout=120s && break
        fi
        sleep 5
        echo -n "."
    done
    ok "ArgoCD Marketplace is ready"
fi

log "Giving ArgoCD time to sync remaining apps (60s)..."
sleep 60

# ──────────────────────────────────────────────────
# Step: Summary
# ──────────────────────────────────────────────────
next_step "Setup Complete! 🎉"

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
if $WITH_MARKETPLACE; then
echo "  │  Marketplace      http://marketplace.localhost   —          │"
fi
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

if ! $WITH_MARKETPLACE; then
    echo -e "${YELLOW}💡 Tip: Run 'make up-marketplace' to add the ArgoCD Marketplace UI (browse & deploy Helm charts).${NC}"
fi
echo -e "${YELLOW}💡 Tip: If *.localhost doesn't resolve, use 'make argocd-ui' for port-forwarding.${NC}"
echo ""
