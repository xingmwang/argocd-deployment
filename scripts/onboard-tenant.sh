#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TENANTS_DIR="$ROOT_DIR/tenants"
TEMPLATE_DIR="$TENANTS_DIR/_template"

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

TARGET_DIR="$TENANTS_DIR/$TEAM_NAME"

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

# Copy template
echo ""
echo "  -> Creating tenant directory..."
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"

# Replace placeholders
echo "  -> Configuring tenant..."
if [[ "$(uname)" == "Darwin" ]]; then
  find "$TARGET_DIR" -type f -name "*.yaml" -exec sed -i '' "s/TEAM_NAME/$TEAM_NAME/g" {} \;
  find "$TARGET_DIR" -type f -name "*.yaml" -exec sed -i '' "s|https://github.com/your-org/TEAM_NAME-\*|${REPO_URL}|g" {} \;
else
  find "$TARGET_DIR" -type f -name "*.yaml" -exec sed -i "s/TEAM_NAME/$TEAM_NAME/g" {} \;
  find "$TARGET_DIR" -type f -name "*.yaml" -exec sed -i "s|https://github.com/your-org/TEAM_NAME-\*|${REPO_URL}|g" {} \;
fi

# Add to bootstrap values
echo "  -> Adding tenant to bootstrap values..."
echo "  - name: $TEAM_NAME
    path: tenants/$TEAM_NAME" >> "$ROOT_DIR/bootstrap/values.yaml"

echo ""
echo "==> Tenant '$TEAM_NAME' created at: $TARGET_DIR"
echo ""
echo "Next steps:"
echo "  1. Review and edit: $TARGET_DIR/project.yaml"
echo "  2. Add your applications under: $TARGET_DIR/apps/"
echo "  3. Commit and push (or open a PR)"
echo ""
