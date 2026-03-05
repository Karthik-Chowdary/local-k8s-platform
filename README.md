# 🚀 Local K8s Platform

**A single-command local Kubernetes platform with GitOps, monitoring, and ingress — ready in minutes.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![K3d](https://img.shields.io/badge/k3d-v5.x-blue)](https://k3d.io)
[![ArgoCD](https://img.shields.io/badge/ArgoCD-v2.14-orange)](https://argoproj.github.io/cd/)
[![Prometheus](https://img.shields.io/badge/Prometheus-Stack-red)](https://prometheus.io/)

> Clone → `make up` → Full platform running. That's it.

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Your Laptop                               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                    Docker Desktop                          │  │
│  │                                                            │  │
│  │  ┌─────────────────────────────────────────────────────┐   │  │
│  │  │              k3d Cluster (k3s-in-Docker)            │   │  │
│  │  │                                                     │   │  │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────┐            │   │  │
│  │  │  │ Server  │  │ Agent 1 │  │ Agent 2 │            │   │  │
│  │  │  └────┬────┘  └────┬────┘  └────┬────┘            │   │  │
│  │  │       │            │            │                   │   │  │
│  │  │  ┌────┴────────────┴────────────┴────┐             │   │  │
│  │  │  │        NGINX Ingress Controller   │             │   │  │
│  │  │  │     (*.localhost → services)      │             │   │  │
│  │  │  └──────────────┬───────────────────-┘             │   │  │
│  │  │                 │                                   │   │  │
│  │  │    ┌────────────┼────────────────────┐             │   │  │
│  │  │    │            │                    │             │   │  │
│  │  │    ▼            ▼                    ▼             │   │  │
│  │  │  ┌──────┐  ┌─────────┐  ┌────────────────┐       │   │  │
│  │  │  │ArgoCD│  │Grafana  │  │ Your Apps      │       │   │  │
│  │  │  │ (UI) │  │Prom/AM  │  │ podinfo, echo  │       │   │  │
│  │  │  └──┬───┘  └─────────┘  └────────────────┘       │   │  │
│  │  │     │                                              │   │  │
│  │  │     ▼  GitOps (app-of-apps)                       │   │  │
│  │  │  ┌──────────────────────────┐                      │   │  │
│  │  │  │  apps/ directory         │                      │   │  │
│  │  │  │  (drop manifests here)   │                      │   │  │
│  │  │  └──────────────────────────┘                      │   │  │
│  │  └─────────────────────────────────────────────────────┘   │  │
│  │                                                            │  │
│  │  ┌──────────────┐                                          │  │
│  │  │ k3d Registry │  (local image cache)                     │  │
│  │  └──────────────┘                                          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Ports: 80 (HTTP) ─────► Ingress Controller                     │
│         443 (HTTPS) ───► Ingress Controller                     │
└──────────────────────────────────────────────────────────────────┘
```

## ✅ Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Docker](https://docs.docker.com/get-docker/) | 20.10+ | Container runtime |
| [k3d](https://k3d.io/) | 5.x | Lightweight K8s clusters |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.27+ | Kubernetes CLI |
| [Helm](https://helm.sh/docs/intro/install/) | 3.12+ | Package manager |

> **Don't have these?** Run `make prerequisites` — it'll check and offer to install what's missing.

## ⚡ Quick Start

```bash
git clone https://github.com/Karthik-Chowdary/local-k8s-platform.git
cd local-k8s-platform
make up
```

That's it. In ~5 minutes you'll have a full platform running.

## 🌐 What You Get

| Service | URL | Credentials |
|---------|-----|-------------|
| **ArgoCD** | [http://argocd.localhost](http://argocd.localhost) | `admin` / `make argocd-password` |
| **Grafana** | [http://grafana.localhost](http://grafana.localhost) | `admin` / `admin` |
| **Prometheus** | [http://prometheus.localhost](http://prometheus.localhost) | — |
| **Alertmanager** | [http://alertmanager.localhost](http://alertmanager.localhost) | — |
| **Podinfo** | [http://podinfo.localhost](http://podinfo.localhost) | — |
| **Echoserver** | [http://echoserver.localhost](http://echoserver.localhost) | — |

> 💡 `*.localhost` resolves to `127.0.0.1` on most systems — no `/etc/hosts` edits needed.

## 📦 What's Included

- **🔄 ArgoCD** — GitOps continuous delivery with app-of-apps pattern
- **📊 Prometheus + Grafana** — Full monitoring stack with pre-built K8s dashboards
- **🚪 NGINX Ingress** — Production-grade ingress controller
- **🎯 Example Apps** — podinfo and echoserver to demonstrate the pattern
- **📁 Extensible** — Drop a YAML in `apps/` to add new applications

## 🛠️ Makefile Targets

```bash
make up                 # Full platform setup (cluster + all apps)
make down               # Tear everything down
make status             # Show URLs, pods, ArgoCD sync status
make prerequisites      # Check/install prerequisites

make argocd-password    # Get ArgoCD admin password
make argocd-ui          # Port-forward ArgoCD (fallback if ingress fails)
make grafana-ui         # Port-forward Grafana

make add-app            # Instructions for adding a new app
make logs               # Tail important pod logs
make help               # Show all available targets
```

## ➕ Adding Your Own Apps

Adding a new app is as simple as creating one YAML file:

```yaml
# apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://my-chart-repo.example.com
    targetRevision: "1.0.0"
    chart: my-app
    helm:
      valueFiles:
        - ../../helm-values/my-app.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: my-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Commit + push → ArgoCD picks it up automatically.

📖 **Full guide:** [docs/ADDING_APPS.md](docs/ADDING_APPS.md)

## 📁 Repository Structure

```
local-k8s-platform/
├── README.md                      # You are here
├── Makefile                       # All automation targets
├── scripts/
│   ├── setup.sh                   # Full setup orchestration
│   ├── teardown.sh                # Clean teardown
│   └── prerequisites.sh           # Prerequisite checker/installer
├── cluster/
│   └── k3d-config.yaml            # k3d cluster configuration
├── bootstrap/
│   ├── argocd/
│   │   ├── namespace.yaml         # ArgoCD namespace
│   │   └── values.yaml            # ArgoCD Helm values
│   └── app-of-apps.yaml           # Root Application (watches apps/)
├── apps/                          # ← Drop new ArgoCD apps here
│   ├── ingress-nginx.yaml         # NGINX Ingress Controller
│   ├── kube-prometheus-stack.yaml # Monitoring stack
│   ├── podinfo.yaml               # Example: podinfo
│   └── echoserver.yaml            # Example: echoserver
├── helm-values/                   # Helm value overrides
│   ├── ingress-nginx.yaml
│   ├── kube-prometheus-stack.yaml
│   ├── podinfo.yaml
│   └── echoserver.yaml
├── docs/
│   ├── ADDING_APPS.md             # How to add apps
│   ├── ARCHITECTURE.md            # Architecture deep-dive
│   └── TROUBLESHOOTING.md         # Common issues & fixes
├── .gitignore
└── LICENSE
```

## 📸 Screenshots

> _Coming soon — PRs welcome!_

## 🔧 Troubleshooting

| Issue | Fix |
|-------|-----|
| Port 80/443 in use | Stop other services or change ports in `cluster/k3d-config.yaml` |
| `*.localhost` not resolving | Add entries to `/etc/hosts` or use `make argocd-ui` for port-forward |
| ArgoCD apps stuck `Progressing` | Check `make logs` — usually waiting for images to pull |
| Docker out of disk | Run `docker system prune -a` |

📖 **Full guide:** [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 🤝 Contributing

Contributions are welcome! Here's how:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Ideas for Contributions

- [ ] Add more example apps (Redis, PostgreSQL, etc.)
- [ ] CI pipeline for validation
- [ ] Automated screenshots
- [ ] Loki for log aggregation
- [ ] Cert-manager for TLS
- [ ] Crossplane for cloud resources
- [ ] Tekton/Argo Workflows for CI

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<p align="center">
  Built with ❤️ for the Kubernetes community<br/>
  <strong>If this helped you, give it a ⭐!</strong>
</p>
