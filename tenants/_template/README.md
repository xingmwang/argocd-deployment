# Tenant Onboarding Template

## How to onboard your team

1. Copy this `_template/` directory to `tenants/your-team-name/`
2. Edit `project.yaml`:
   - Set your allowed namespaces (must match `your-team-name-*` prefix)
   - Set your allowed source repositories
3. Add Application YAMLs under `apps/`:
   - One YAML per application
   - Each must target namespaces allowed by your AppProject
4. Open a Pull Request
5. CI will validate your configuration automatically
6. Platform team reviews and merges
7. Argo CD syncs your AppProject and Applications

## Rules

- Namespace prefix must match your team folder name
- No cluster-scoped resources (ClusterRole, ClusterRoleBinding, etc.)
- Source repos must be from the approved organization
- Resource quotas are required
- No wildcard `*` in destinations
