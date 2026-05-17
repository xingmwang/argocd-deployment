#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS=0

echo "==> Validating argocd-deployment repository"
echo ""

# --- YAML Lint ---
echo "  [1/4] YAML syntax check..."
if command -v yamllint &>/dev/null; then
  yamllint -d relaxed "$ROOT_DIR" 2>&1 | head -20 || ((ERRORS++))
else
  echo "  (yamllint not installed, skipping)"
fi

# --- Helm template validation ---
echo "  [2/4] Helm template validation..."
if command -v helm &>/dev/null; then
  # Platform chart
  helm dependency update "$ROOT_DIR/platform/" --skip-refresh 2>/dev/null
  helm template test "$ROOT_DIR/platform/" \
    -f "$ROOT_DIR/platform/values/base.yaml" \
    -f "$ROOT_DIR/platform/values/overlays/dev.yaml" \
    > /dev/null 2>&1 || { echo "    FAIL: platform/ template error"; ((ERRORS++)); }
  echo "    OK: platform/"

  # Bootstrap chart
  helm template test "$ROOT_DIR/bootstrap/" \
    > /dev/null 2>&1 || { echo "    FAIL: bootstrap/ template error"; ((ERRORS++)); }
  echo "    OK: bootstrap/"
else
  echo "  (helm not installed, skipping)"
fi

# --- Tenant validation ---
echo "  [3/4] Tenant apps validation..."
for tenant_dir in "$ROOT_DIR/tenants"/*/; do
  tenant_name=$(basename "$tenant_dir")

  apps_dir="$tenant_dir/apps"
  if [[ ! -d "$apps_dir" ]]; then
    echo "    FAIL: $tenant_name missing apps/ directory"
    ((ERRORS++))
    continue
  fi

  # Check each app YAML has correct metadata.namespace
  for app_file in "$apps_dir"/*.yaml; do
    [[ -f "$app_file" ]] || continue
    app_ns=$(grep -m1 '^\s*namespace:' "$app_file" | awk '{print $2}' | tr -d '"')
    if [[ "$app_ns" != "$tenant_name" ]]; then
      echo "    WARN: $(basename "$app_file") metadata.namespace=$app_ns (expected: $tenant_name)"
    fi
  done

  echo "    OK: $tenant_name"
done

# --- Check for secrets ---
echo "  [4/4] Checking for exposed secrets..."
if grep -rn "password\|secret\|token\|apikey\|api_key" "$ROOT_DIR" \
  --include="*.yaml" --include="*.yml" \
  | grep -v "example\|REDACTED\|template\|README\|\.example\|secretType\|secret-type\|argocd-initial-admin-secret\|clientSecret: \\\$" \
  | grep -iv "secretName\|secretRef\|secretKeyRef" \
  | head -5; then
  echo "    WARN: Potential secrets detected (review above)"
else
  echo "    OK: No exposed secrets found"
fi

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "==> FAILED: $ERRORS error(s) found"
  exit 1
else
  echo "==> PASSED: All checks OK"
fi
