# Argo CD Enterprise Self-Service Deployment

> Structure that scales without refactoring.

An opinionated, production-ready repository template for deploying Argo CD with self-service tenant onboarding, one-command upgrades, and toggleable extensions.

## Architecture

```
argocd-deployment/
├── platform/          Argo CD itself (Helm subchart)
├── bootstrap/         App-of-Apps root (generates Applications)
├── extensions/        Optional features (image-updater, notifications, dex, vault)
├── tenants/           Self-service area (teams onboard via PR)
├── clusters/          Multi-cluster registry (add folder per cluster)
├── scripts/           Automation (install, upgrade, onboard, validate)
└── Makefile           Developer interface
```

## Quick Start (5 minutes)

### Prerequisites

- Kubernetes cluster (or `kind` for local dev)
- Helm 3.x
- kubectl configured with cluster-admin

### Local Development

```bash
# Create a local cluster
make local-cluster

# Install Argo CD
make install ENV=dev

# Access the UI
kubectl port-forward svc/argocd-argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

### Production

```bash
make install ENV=prod
```

## Key Operations

### Upgrade Argo CD

1. Edit version in `platform/Chart.yaml`
2. Run `make upgrade ENV=prod`
3. Done. No manual patching, no drift.

### Onboard a Tenant Team

```bash
make add-tenant
# Follow the interactive prompts
```

Or manually:
1. Copy `tenants/_template/` to `tenants/your-team/`
2. Edit `project.yaml` (set namespaces, repos)
3. Add Application YAMLs under `apps/`
4. Open a PR — CI validates automatically
5. Merge — Argo CD syncs immediately

### Add an Extension

1. Create extension directory under `extensions/`
2. Add entry to `bootstrap/values.yaml` under `extensions:`
3. Commit and push — Argo CD deploys automatically

### Remove an Extension

1. Remove the entry from `bootstrap/values.yaml`
2. Commit and push — `prune: true` cleans up cluster resources automatically

## Design Principles

| Principle | Implementation |
|-----------|---------------|
| Easy to upgrade | Helm subchart — change version number, `make upgrade` |
| Easy to extend | Add folder + values entry, no restructuring needed |
| Self-service | Tenant teams PR in their apps, platform team reviews |
| Multi-cluster ready | `clusters/` directory, designed for Hub-and-Spoke |
| Explicit over magic | Every Application is a readable YAML file |
| Secure by default | AppProject constraints, validation scripts, no wildcards |

## Values Overlay Strategy

```
platform/values/
├── base.yaml              Defaults for all environments
└── overlays/
    ├── dev.yaml           Single replica, debug logging, NodePort
    ├── staging.yaml       HA test, mirrors prod config
    └── prod.yaml          Full HA, strict resources, ingress
```

Only override what differs from base. Helm deep-merges the rest.

## Tenant Guardrails

The validation script (`scripts/validate.sh`) enforces:

- Namespace prefix must match tenant folder name
- No cluster-scoped resources allowed
- Source repos must be from approved organization
- No wildcard `*` in destinations

## Directory Ownership

| Directory | Owner | Access Model |
|-----------|-------|-------------|
| `platform/` | Platform team | Direct commit |
| `bootstrap/` | Platform team | Direct commit |
| `extensions/` | Platform team | Direct commit |
| `tenants/{team}/` | Tenant team | PR + review |
| `clusters/` | Platform team | Direct commit |
| `scripts/` | Platform team | Direct commit |

## License

Apache 2.0
