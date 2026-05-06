#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ERRORS=0

echo "==> Validating argocd-deployment repository"
echo ""

# --- YAML Lint ---
echo "  [1/5] YAML syntax check..."
if command -v yamllint &>/dev/null; then
  yamllint -d relaxed "$ROOT_DIR" 2>&1 | head -20 || ((ERRORS++))
else
  echo "  (yamllint not installed, skipping)"
fi

# --- Helm template validation ---
echo "  [2/5] Helm template validation (platform)..."
if command -v helm &>/dev/null; then
  helm dependency update "$ROOT_DIR/platform/" --skip-refresh 2>/dev/null
  helm template test "$ROOT_DIR/platform/" \
    -f "$ROOT_DIR/platform/values/base.yaml" \
    -f "$ROOT_DIR/platform/values/overlays/dev.yaml" \
    > /dev/null 2>&1 || { echo "    FAIL: platform/ template error"; ((ERRORS++)); }
  echo "    OK"
else
  echo "  (helm not installed, skipping)"
fi

# --- Tenant validation ---
echo "  [3/5] Tenant AppProject constraints..."
for tenant_dir in "$ROOT_DIR/tenants"/*/; do
  tenant_name=$(basename "$tenant_dir")
  [[ "$tenant_name" == "_template" ]] && continue

  project_file="$tenant_dir/project.yaml"
  if [[ ! -f "$project_file" ]]; then
    echo "    FAIL: $tenant_name missing project.yaml"
    ((ERRORS++))
    continue
  fi

  # Check namespace prefix matches tenant name
  if grep -q "namespace:" "$project_file"; then
    namespaces=$(grep "namespace:" "$project_file" | grep -v "^  namespace: argocd")
    if echo "$namespaces" | grep -v "${tenant_name}" | grep -qv "^\s*#"; then
      echo "    WARN: $tenant_name may have namespaces not matching prefix"
    fi
  fi

  # Check no cluster-scoped resources
  if grep -q "clusterResourceWhitelist" "$project_file"; then
    if grep -A2 "clusterResourceWhitelist" "$project_file" | grep -q "kind:"; then
      echo "    FAIL: $tenant_name has cluster-scoped resources allowed"
      ((ERRORS++))
    fi
  fi

  echo "    OK: $tenant_name"
done

# --- Check for secrets ---
echo "  [4/5] Checking for exposed secrets..."
if grep -rn "password\|secret\|token\|apikey\|api_key" "$ROOT_DIR" \
  --include="*.yaml" --include="*.yml" \
  | grep -v "example\|REDACTED\|template\|README\|\.example\|secretType\|secret-type\|argocd-initial-admin-secret\|clientSecret: \\\$" \
  | grep -iv "secretName\|secretRef\|secretKeyRef" \
  | head -5; then
  echo "    WARN: Potential secrets detected (review above)"
else
  echo "    OK: No exposed secrets found"
fi

# --- Shell scripts ---
echo "  [5/5] Shellcheck..."
if command -v shellcheck &>/dev/null; then
  shellcheck "$ROOT_DIR/scripts/"*.sh 2>&1 | head -20 || ((ERRORS++))
  echo "    OK"
else
  echo "  (shellcheck not installed, skipping)"
fi

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "==> FAILED: $ERRORS error(s) found"
  exit 1
else
  echo "==> PASSED: All checks OK"
fi
