#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALUES_FILE="$ROOT_DIR/bootstrap/values.yaml"

echo "==> Tenant Onboarding"
echo ""

# Get team name
read -rp "Team name (lowercase, no spaces): " TEAM_NAME

if [[ -z "$TEAM_NAME" ]]; then
  echo "Error: Team name is required"
  exit 1
fi

if [[ ! "$TEAM_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "Error: Team name must be lowercase alphanumeric with hyphens only"
  exit 1
fi

TARGET_DIR="$ROOT_DIR/tenants/$TEAM_NAME/apps"

if [[ -d "$TARGET_DIR" ]]; then
  echo "Error: Tenant '$TEAM_NAME' already exists at $TARGET_DIR"
  exit 1
fi

# Get source repo
read -rp "Source repo URL (e.g., https://github.com/org/repo.git): " REPO_URL

if [[ -z "$REPO_URL" ]]; then
  echo "Error: Source repo URL is required"
  exit 1
fi

# Create tenant apps directory
echo ""
echo "  -> Creating tenant directory..."
mkdir -p "$TARGET_DIR"

# Create a sample app placeholder
cat > "$TARGET_DIR/.gitkeep" <<EOF
EOF

# Add to bootstrap values
echo "  -> Adding tenant to bootstrap/values.yaml..."
cat >> "$VALUES_FILE" <<EOF
  - name: $TEAM_NAME
    namespace: $TEAM_NAME
    path: tenants/$TEAM_NAME
    sourceRepos:
      - "$REPO_URL"
EOF

echo ""
echo "==> Tenant '$TEAM_NAME' created!"
echo ""
echo "Next steps:"
echo "  1. Add Application YAML files under: tenants/$TEAM_NAME/apps/"
echo "  2. Apply bootstrap: helm template bootstrap bootstrap/ | kubectl apply -f -"
echo "  3. Commit and push"
echo ""
echo "Example app file (tenants/$TEAM_NAME/apps/my-app-dev.yaml):"
echo ""
echo "  apiVersion: argoproj.io/v1alpha1"
echo "  kind: Application"
echo "  metadata:"
echo "    name: ${TEAM_NAME}-my-app-dev"
echo "    namespace: ${TEAM_NAME}"
echo "  spec:"
echo "    project: ${TEAM_NAME}"
echo "    source:"
echo "      repoURL: \"$REPO_URL\""
echo "      targetRevision: HEAD"
echo "      path: deploy/dev"
echo "    destination:"
echo "      server: https://kubernetes.default.svc"
echo "      namespace: ${TEAM_NAME}-dev"
echo "    syncPolicy:"
echo "      automated:"
echo "        prune: true"
echo "        selfHeal: true"
echo "      syncOptions:"
echo "        - CreateNamespace=true"
echo ""
