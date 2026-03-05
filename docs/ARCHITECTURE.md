# 🏗️ Architecture Deep Dive

## Overview

This platform provides a complete local Kubernetes environment using the same patterns and tools found in production clusters. Everything runs inside Docker on your machine.

## Component Stack

```
┌──────────────────────────────────────────────────────────────────────┐
│                            LAYER 4: APPS                            │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐  ┌────────────────────┐ │
│  │ podinfo  │  │echoserver │  │ your-app │  │  drop YAML here!  │ │
│  └──────────┘  └───────────┘  └──────────┘  └────────────────────┘ │
├──────────────────────────────────────────────────────────────────────┤
│                         LAYER 3: PLATFORM                           │
│  ┌──────────────┐  ┌─────────────────────────────────────────────┐  │
│  │   ArgoCD     │  │      kube-prometheus-stack                  │  │
│  │ (GitOps CD)  │  │  Prometheus │ Grafana │ Alertmanager        │  │
│  └──────────────┘  └─────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────────────────┤
│                         LAYER 2: INGRESS                            │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              NGINX Ingress Controller                         │   │
│  │         *.localhost → Service routing                         │   │
│  └──────────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────────┤
│                        LAYER 1: CLUSTER                             │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │              k3d (k3s-in-Docker)                              │   │
│  │    1 Server + 2 Agents + LoadBalancer + Registry              │   │
│  └──────────────────────────────────────────────────────────────┘   │
├──────────────────────────────────────────────────────────────────────┤
│                        LAYER 0: HOST                                │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    Docker Engine                               │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

## k3d Cluster

[k3d](https://k3d.io) runs k3s (a lightweight Kubernetes distribution) inside Docker containers. This gives us:

- **Fast startup** — Cluster ready in ~30 seconds
- **No VM overhead** — Direct container execution
- **Multi-node** — 1 server + 2 agents simulate a real cluster
- **Port mapping** — Host ports 80/443 → k3d loadbalancer → ingress controller
- **Local registry** — `registry.localhost:5111` for fast image pushes

### Cluster Configuration

```
Server Node (control plane)
├── API Server
├── etcd (embedded SQLite in k3s)
├── Controller Manager
└── Scheduler

Agent Node 1 (worker)
├── kubelet
└── containerd

Agent Node 2 (worker)
├── kubelet
└── containerd

LoadBalancer (k3d serverlb)
├── Port 80 → NodePort → Ingress Controller
└── Port 443 → NodePort → Ingress Controller

Registry (registry.localhost)
└── Port 5111 → local container registry
```

### Why k3d over Minikube/Kind?

| Feature | k3d | Minikube | Kind |
|---------|-----|----------|------|
| Startup time | ~30s | ~2min | ~1min |
| Multi-node | ✅ | ✅ (limited) | ✅ |
| LoadBalancer | ✅ (built-in) | ❌ (needs tunnel) | ❌ (needs metallb) |
| Registry | ✅ (built-in) | ✅ (addon) | ❌ (manual) |
| Memory overhead | Low | High (VM) | Low |
| Port mapping | ✅ (native) | ⚠️ (tunnel) | ✅ (manual) |

## ArgoCD & App-of-Apps Pattern

### How It Works

```
bootstrap/app-of-apps.yaml
         │
         ▼
   ArgoCD Root Application
   (watches apps/ directory)
         │
         ├──► apps/ingress-nginx.yaml      → Ingress Controller
         ├──► apps/kube-prometheus-stack.yaml → Monitoring
         ├──► apps/podinfo.yaml             → Example App
         └──► apps/echoserver.yaml          → Example App
```

The **root Application** (`app-of-apps.yaml`) points to the `apps/` directory in this Git repo. ArgoCD watches this directory and creates/updates/deletes Application resources as files change.

Each Application in `apps/` can reference:
- A **Helm chart** from a remote registry
- **Raw manifests** from a directory in this repo
- **Kustomize** overlays

### Sync Waves

Applications deploy in order using sync-wave annotations:

1. **Wave -1**: Ingress Controller (needed by other apps for routing)
2. **Wave 0**: Monitoring stack (infrastructure)
3. **Wave 1**: User applications (podinfo, echoserver)

## Networking

### Request Flow

```
Browser: http://podinfo.localhost
    │
    ▼
Host OS resolves *.localhost → 127.0.0.1
    │
    ▼
Docker port mapping: 0.0.0.0:80 → k3d-loadbalancer:80
    │
    ▼
k3d loadbalancer → NodePort on agents
    │
    ▼
NGINX Ingress Controller
    │ (matches Host: podinfo.localhost)
    ▼
podinfo Service → podinfo Pods
```

### DNS Resolution

`*.localhost` resolves to `127.0.0.1` on most modern operating systems:
- **Linux**: Via systemd-resolved or NSS (RFC 6761)
- **macOS**: Built-in (since 10.x)
- **Windows**: May need `/etc/hosts` entries

If `*.localhost` doesn't work, add to `/etc/hosts`:
```
127.0.0.1 argocd.localhost grafana.localhost prometheus.localhost alertmanager.localhost podinfo.localhost echoserver.localhost
```

## Monitoring Stack

The `kube-prometheus-stack` deploys:

| Component | Purpose | URL |
|-----------|---------|-----|
| **Prometheus** | Metrics collection & alerting rules | prometheus.localhost |
| **Grafana** | Dashboards & visualization | grafana.localhost |
| **Alertmanager** | Alert routing & silencing | alertmanager.localhost |
| **Node Exporter** | Host-level metrics | (internal) |
| **kube-state-metrics** | Kubernetes object metrics | (internal) |
| **Prometheus Operator** | Manages Prometheus via CRDs | (internal) |

### Pre-built Dashboards

Grafana comes with dashboards for:
- Kubernetes cluster overview
- Node resource usage
- Pod/container metrics
- Namespace resource quotas
- ArgoCD application status (via Grafana.com dashboard #14584)

### ServiceMonitor Auto-Discovery

Prometheus is configured to discover all `ServiceMonitor` resources across all namespaces. When you deploy a new app with a `ServiceMonitor`, Prometheus will automatically scrape it.

## Security Notes

This is a **local development** platform. Security trade-offs made for convenience:

| Setting | Value | Why |
|---------|-------|-----|
| ArgoCD TLS | Disabled | No need for HTTPS on localhost |
| Grafana password | `admin` | Easy access for development |
| RBAC | Default | k3s defaults are fine for local |
| Network policies | None | Not needed for local dev |
| Secrets encryption | None | No sensitive data |

**⚠️ Do NOT use this configuration in production.** See the [ArgoCD production guide](https://argo-cd.readthedocs.io/en/stable/operator-manual/) for hardening.
