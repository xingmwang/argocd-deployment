# Multi-Cluster Management

## Registering a New Cluster

1. Copy `_template/` to a new directory named after your cluster
2. Edit `config.yaml` with the cluster's metadata
3. Register the cluster with Argo CD:
   ```bash
   argocd cluster add <kubectl-context-name> --name <cluster-name>
   ```
4. Commit the config.yaml (metadata only, no secrets)

## Important Notes

- Use cluster **names** (not URLs) in Application destinations for portability
- Keep namespace naming consistent across clusters (e.g., `order-system` everywhere)
- Never commit cluster secrets to git — use sealed-secrets or external-secrets-operator
