# 🔧 Troubleshooting Guide

## Quick Diagnostics

Run these first:

```bash
# Overall status
make status

# Check all pods
kubectl get pods -A

# Check ArgoCD applications
kubectl get applications -n argocd

# Check events for errors
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

---

## Common Issues

### 🔴 Port 80/443 Already in Use

**Symptoms:** k3d cluster creation fails with "port already in use"

**Fix:**
```bash
# Find what's using port 80
sudo lsof -i :80
# or
sudo ss -tlnp | grep ':80'

# Common culprits: Apache, Nginx, Docker containers
# Stop them or change k3d ports:
```

Edit `cluster/k3d-config.yaml`:
```yaml
ports:
  - port: 8080:80     # Use 8080 instead
    nodeFilters:
      - loadbalancer
  - port: 8443:443    # Use 8443 instead
    nodeFilters:
      - loadbalancer
```

Then access apps at `http://argocd.localhost:8080` etc.

### 🔴 `*.localhost` Not Resolving

**Symptoms:** Browser shows "site can't be reached" for `argocd.localhost`

**Fix 1:** Add entries to `/etc/hosts`:
```bash
echo "127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost alertmanager.localhost podinfo.localhost echoserver.localhost" | sudo tee -a /etc/hosts
```

**Fix 2:** Use port-forwarding instead:
```bash
make argocd-ui    # ArgoCD at localhost:8080
make grafana-ui   # Grafana at localhost:3000
```

### 🔴 Docker Out of Disk Space

**Symptoms:** Pods stuck in `Pending` or `ImagePullBackOff`

**Fix:**
```bash
# Check Docker disk usage
docker system df

# Clean up
docker system prune -a --volumes

# Recreate cluster
make down && make up
```

### 🔴 ArgoCD Apps Stuck in "Progressing"

**Symptoms:** Applications show `Progressing` forever in ArgoCD UI

**Common causes:**
1. **Images still pulling** — Wait a few minutes, especially on first run
2. **Resource constraints** — Your machine may be running low on RAM

**Debug:**
```bash
# Check which pods are pending
kubectl get pods -A | grep -v Running

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"
```

### 🔴 ArgoCD Can't Reach GitHub

**Symptoms:** App-of-apps shows sync error about repository

**Fix:** The app-of-apps references this GitHub repo. If it's private or not yet pushed:

```bash
# Option 1: Make the repo public on GitHub

# Option 2: Add repo credentials to ArgoCD
kubectl -n argocd create secret generic repo-creds \
    --from-literal=url=https://github.com/Karthik-Chowdary/local-k8s-platform.git \
    --from-literal=username=<github-user> \
    --from-literal=password=<github-pat>
kubectl -n argocd label secret repo-creds argocd.argoproj.io/secret-type=repository
```

### 🟡 Prometheus Targets Down

**Symptoms:** Prometheus shows targets as `DOWN`

**Common in k3s:**
- `kube-controller-manager` — Not exposed in k3s (disabled in our config)
- `kube-scheduler` — Not exposed in k3s (disabled in our config)
- `kube-proxy` — k3s doesn't run kube-proxy by default (disabled in our config)
- `etcd` — k3s uses embedded SQLite (disabled in our config)

These are expected and harmless.

### 🟡 Webhook Errors During Sync

**Symptoms:** ArgoCD shows webhook validation errors during ingress-nginx install

**Fix:** This is usually a timing issue. The admission webhook isn't ready yet.

```bash
# Retry the sync
kubectl get application ingress-nginx -n argocd -o json | \
    jq '.metadata.annotations["argocd.argoproj.io/refresh"] = "hard"' | \
    kubectl apply -f -
```

Or delete and recreate:
```bash
kubectl delete application ingress-nginx -n argocd
# Wait for app-of-apps to recreate it
```

### 🟡 Slow First Start

**Symptoms:** Setup takes 10+ minutes on first run

**Why:** Docker needs to pull many images:
- k3s node images (~200MB each × 3 nodes)
- ArgoCD components
- NGINX Ingress Controller
- Prometheus + Grafana + exporters
- Example apps

**Mitigation:** The local registry (`registry.localhost:5111`) caches images. Second start is much faster.

### 🔴 `make down` Didn't Clean Up Everything

**Symptoms:** Leftover Docker containers or networks

**Nuclear option:**
```bash
# Delete cluster
k3d cluster delete local-k8s-platform

# Remove ALL k3d resources
k3d cluster delete --all
k3d registry delete --all

# Clean Docker
docker system prune -a --volumes
```

---

## Useful Debug Commands

```bash
# ArgoCD CLI (if installed)
argocd app list --server localhost:8080 --insecure
argocd app get <app-name> --server localhost:8080 --insecure

# Logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server -f
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller -f
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# Resources
kubectl top pods -A --sort-by=memory
kubectl top nodes

# Events
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# ArgoCD application details
kubectl get applications -n argocd -o yaml

# Ingress configuration
kubectl get ingress -A
kubectl describe ingress -A
```

## Getting Help

1. Check this guide first
2. Look at [ArgoCD docs](https://argo-cd.readthedocs.io/)
3. Check [k3d docs](https://k3d.io/)
4. Open an issue on this repository
