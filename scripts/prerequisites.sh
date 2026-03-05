#!/usr/bin/env bash
# prerequisites.sh — Check and optionally install prerequisites
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

MISSING=()

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  🔍 Checking Prerequisites${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Docker
if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    ok "Docker ${DOCKER_VERSION}"
    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        fail "Docker daemon is not running"
        echo "  Start Docker Desktop or run: sudo systemctl start docker"
        exit 1
    fi
    ok "Docker daemon is running"
else
    fail "Docker not found"
    MISSING+=("docker")
fi

# k3d
if command -v k3d &>/dev/null; then
    K3D_VERSION=$(k3d --version | grep -oP 'v[\d.]+' | head -1)
    ok "k3d ${K3D_VERSION}"
else
    fail "k3d not found"
    MISSING+=("k3d")
fi

# kubectl
if command -v kubectl &>/dev/null; then
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -oP '"gitVersion":\s*"[^"]*"' | grep -oP 'v[\d.]+' | head -1)
    ok "kubectl ${KUBECTL_VERSION}"
else
    fail "kubectl not found"
    MISSING+=("kubectl")
fi

# Helm
if command -v helm &>/dev/null; then
    HELM_VERSION=$(helm version --short 2>/dev/null | grep -oP 'v[\d.]+' | head -1)
    ok "Helm ${HELM_VERSION}"
else
    fail "Helm not found"
    MISSING+=("helm")
fi

echo ""

# If anything is missing, offer to install
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${YELLOW}Missing tools: ${MISSING[*]}${NC}"
    echo ""
    read -rp "Install missing tools? [y/N] " INSTALL
    if [[ "${INSTALL,,}" == "y" ]]; then
        for tool in "${MISSING[@]}"; do
            case "$tool" in
                docker)
                    log "Installing Docker..."
                    curl -fsSL https://get.docker.com | sh
                    sudo usermod -aG docker "$USER"
                    ok "Docker installed (you may need to log out and back in)"
                    ;;
                k3d)
                    log "Installing k3d..."
                    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
                    ok "k3d installed"
                    ;;
                kubectl)
                    log "Installing kubectl..."
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
                    rm -f kubectl
                    ok "kubectl installed"
                    ;;
                helm)
                    log "Installing Helm..."
                    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                    ok "Helm installed"
                    ;;
            esac
        done
        echo ""
        log "All tools installed. Re-run this script to verify."
    else
        fail "Please install missing tools and try again."
        exit 1
    fi
else
    echo -e "${GREEN}All prerequisites met! ✅${NC}"
fi

echo ""
