# ➕ Adding Applications

This guide walks you through adding a new application to the platform. Thanks to the **app-of-apps** pattern, it's as simple as dropping a YAML file in the `apps/` directory.

## How It Works

```
You create apps/my-app.yaml
        │
        ▼
Git push to main branch
        │
        ▼
ArgoCD root app detects change
        │
        ▼
ArgoCD creates Application resource
        │
        ▼
ArgoCD syncs your app to the cluster
        │
        ▼
App is running! 🎉
```

## Step-by-Step Guide

### 1. Choose Your Source Type

ArgoCD supports multiple source types:

| Type | Use When |
|------|----------|
| **Helm Chart** (remote) | App has a public Helm chart |
| **Helm Chart** (local) | You have custom charts in this repo |
| **Raw Manifests** | You have plain YAML files |
| **Kustomize** | You use Kustomize overlays |

### 2. Create the Application Manifest

#### Option A: Helm Chart (Remote Repository)

```yaml
# apps/redis.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: redis
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://charts.bitnami.com/bitnami
    targetRevision: "19.6.0"
    chart: redis
    helm:
      releaseName: redis
      values: |
        architecture: standalone
        auth:
          enabled: false
        master:
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 256Mi
  destination:
    server: https://kubernetes.default.svc
    namespace: redis
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

#### Option B: Raw Manifests (In This Repo)

1. Create a directory under `manifests/`:

```bash
mkdir -p manifests/my-app
```

2. Add your Kubernetes manifests:

```yaml
# manifests/my-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-image:latest
          ports:
            - containerPort: 8080
---
# manifests/my-app/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: my-app
spec:
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

3. Create the ArgoCD Application:

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
    repoURL: https://github.com/Karthik-Chowdary/local-k8s-platform.git
    targetRevision: main
    path: manifests/my-app
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

#### Option C: Kustomize

```yaml
# apps/my-kustomize-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-kustomize-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/Karthik-Chowdary/local-k8s-platform.git
    targetRevision: main
    path: kustomize/my-app/overlays/local
  destination:
    server: https://kubernetes.default.svc
    namespace: my-kustomize-app
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### 3. Add Ingress (Optional)

If your app needs a web UI, add an Ingress resource:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: my-app
spec:
  ingressClassName: nginx
  rules:
    - host: my-app.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

### 4. Commit and Push

```bash
git add apps/my-app.yaml manifests/my-app/  # if using raw manifests
git commit -m "feat: add my-app"
git push
```

### 5. Verify

ArgoCD will automatically detect and sync your new application:

```bash
# Check ArgoCD
kubectl get applications -n argocd

# Or visit the ArgoCD UI
open http://argocd.localhost
```

## Sync Waves

Use sync-wave annotations to control deployment order:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

| Wave | Purpose |
|------|---------|
| `-1` | Infrastructure (ingress, cert-manager) |
| `0` | Core services (monitoring, logging) |
| `1` | Applications |
| `2+` | Dependent applications |

## Tips

- **Always include `finalizers`** — ensures clean deletion when you remove the app
- **Use `CreateNamespace=true`** — so you don't need to pre-create namespaces
- **Set `automated.prune: true`** — removes resources that are deleted from Git
- **Set `automated.selfHeal: true`** — reverts manual changes to match Git
- **Use `ServerSideApply=true`** — for CRD-heavy charts (monitoring, etc.)

## Removing an App

1. Delete the file from `apps/`
2. Commit and push
3. ArgoCD will prune the application and all its resources (thanks to finalizers)
