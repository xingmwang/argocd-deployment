#!/bin/bash
set -euo pipefail

ENV=${1:-dev}
NAMESPACE=argocd
RELEASE=argocd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Upgrading Argo CD (env: $ENV)"

# 1. Build Helm dependencies (version-aware, only pull if needed)
CHART_VERSION=$(grep -A3 'dependencies:' "$ROOT_DIR/platform/Chart.yaml" | grep 'version:' | awk '{print $2}' | tr -d '"')
CHART_FILE="$ROOT_DIR/platform/charts/argo-cd-${CHART_VERSION}.tgz"

echo "  -> Required chart: argo-cd-${CHART_VERSION}"
if [[ -f "$CHART_FILE" ]]; then
  echo "  -> Chart already exists locally, skipping download"
else
  echo "  -> Chart not found locally, downloading..."
  mkdir -p "$ROOT_DIR/platform/charts"
  helm repo add argo-helm https://argoproj.github.io/argo-helm || {
    echo "ERROR: Cannot reach argo-helm repo. Download the chart manually:"
    echo "  curl -L -o platform/charts/argo-cd-${CHART_VERSION}.tgz \\"
    echo "    https://github.com/argoproj/argo-helm/releases/download/argo-cd-${CHART_VERSION}/argo-cd-${CHART_VERSION}.tgz"
    exit 1
  }
  helm repo update argo-helm
  helm pull argo-cd --repo https://argoproj.github.io/argo-helm --version "$CHART_VERSION" -d "$ROOT_DIR/platform/charts/"
fi

# 2. Show what will change
echo "  -> Diffing changes..."
helm diff upgrade "$RELEASE" "$ROOT_DIR/platform/" \
  -n "$NAMESPACE" \
  -f "$ROOT_DIR/platform/values/base.yaml" \
  -f "$ROOT_DIR/platform/values/overlays/${ENV}.yaml" 2>/dev/null || echo "  (helm-diff plugin not installed, skipping diff)"

# 3. Upgrade
echo "  -> Running helm upgrade..."
helm upgrade "$RELEASE" "$ROOT_DIR/platform/" \
  -n "$NAMESPACE" \
  -f "$ROOT_DIR/platform/values/base.yaml" \
  -f "$ROOT_DIR/platform/values/overlays/${ENV}.yaml" \
  --wait

# 4. Verify
echo "  -> Verifying deployment..."
kubectl -n "$NAMESPACE" rollout status deployment "${RELEASE}-argocd-server" --timeout=120s

echo ""
echo "==> Upgrade complete!"
