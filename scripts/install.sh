#!/bin/bash
set -euo pipefail

ENV=${1:-dev}
NAMESPACE=${ARGOCD_NAMESPACE:-argocd}
RELEASE=argocd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Installing Argo CD (env: $ENV, namespace: $NAMESPACE)"

# 1. Create namespace
echo "  -> Creating namespace..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# 2. Build Helm dependencies (version-aware, only pull if needed)
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

# 3. Install or upgrade Argo CD via Helm
echo "  -> Installing/Upgrading Argo CD..."
helm upgrade --install "$RELEASE" "$ROOT_DIR/platform/" \
  -n "$NAMESPACE" \
  -f "$ROOT_DIR/platform/values/base.yaml" \
  -f "$ROOT_DIR/platform/values/overlays/${ENV}.yaml" \
  --wait

# 4. Wait for Argo CD server to be ready
echo "  -> Waiting for Argo CD server..."
kubectl -n "$NAMESPACE" rollout status deployment "${RELEASE}-server" --timeout=120s

# 5. Apply bootstrap (Namespaces + AppProjects + tenant Applications)
echo "  -> Applying bootstrap resources..."
helm template bootstrap "$ROOT_DIR/bootstrap/" | kubectl apply -f -

echo ""
echo "==> Done! Argo CD is running and tenants are configured."
echo ""
echo "Access the UI:"
echo "  kubectl port-forward svc/${RELEASE}-server -n $NAMESPACE 8080:443"
echo ""
echo "Get admin password:"
echo "  kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""
