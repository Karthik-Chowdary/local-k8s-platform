#!/usr/bin/env bash
# teardown.sh — Clean teardown of the local k8s platform
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[✓]${NC}     $*"; }
warn() { echo -e "${YELLOW}[!]${NC}     $*"; }
fail() { echo -e "${RED}[✗]${NC}     $*"; }

CLUSTER_NAME="local-k8s-platform"

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  🗑️  Tearing Down Platform${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    log "Deleting k3d cluster '$CLUSTER_NAME'..."
    k3d cluster delete "$CLUSTER_NAME"
    ok "Cluster deleted"
else
    warn "Cluster '$CLUSTER_NAME' not found — nothing to delete"
fi

# Clean up any k3d registry
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "registry.localhost"; then
    log "Removing local registry..."
    docker rm -f registry.localhost 2>/dev/null || true
    ok "Registry removed"
fi

# Remove kubeconfig context
if kubectl config get-contexts -o name 2>/dev/null | grep -q "k3d-${CLUSTER_NAME}"; then
    log "Removing kubeconfig context..."
    kubectl config delete-context "k3d-${CLUSTER_NAME}" 2>/dev/null || true
    kubectl config delete-cluster "k3d-${CLUSTER_NAME}" 2>/dev/null || true
    ok "Kubeconfig cleaned"
fi

echo ""
echo -e "${GREEN}✅ Teardown complete!${NC}"
echo -e "${YELLOW}💡 Run 'docker system prune' to reclaim disk space if needed.${NC}"
echo ""
