#!/usr/bin/env bash
set -euo pipefail

# Install shared model platform services. The namespace intentionally remains
# gourmetgram-platform because the existing training workflows and slides refer
# to that service namespace for MLflow and MinIO.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-}"
FLOATING_IP="${FLOATING_IP:-${1:-}}"
MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-your-access-key}"
MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-PL89sTsyClxjtvQVxjN9}"
POSTGRES_USER="${POSTGRES_USER:-mlflow}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-mlflow}"
POSTGRES_DB="${POSTGRES_DB:-mlflow}"

if [[ -z "${KUBECONFIG_PATH}" && -f /etc/kubernetes/admin.conf ]]; then
  KUBECONFIG_PATH=/etc/kubernetes/admin.conf
fi

kubectl_args=()
helm_args=()
if [[ -n "${KUBECONFIG_PATH}" ]]; then
  kubectl_args+=(--kubeconfig "${KUBECONFIG_PATH}")
  helm_args+=(--kubeconfig "${KUBECONFIG_PATH}")
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required for platform installation. Install Helm on node1 first." >&2
  exit 1
fi

kubectl "${kubectl_args[@]}" create namespace gourmetgram-platform --dry-run=client -o yaml | kubectl "${kubectl_args[@]}" apply -f -
kubectl "${kubectl_args[@]}" -n gourmetgram-platform create secret generic minio-credentials \
  --from-literal=accesskey="${MINIO_ACCESS_KEY}" \
  --from-literal=secretkey="${MINIO_SECRET_KEY}" \
  --dry-run=client -o yaml | kubectl "${kubectl_args[@]}" apply -f -
kubectl "${kubectl_args[@]}" -n gourmetgram-platform create secret generic postgres-credentials \
  --from-literal=username="${POSTGRES_USER}" \
  --from-literal=password="${POSTGRES_PASSWORD}" \
  --from-literal=dbname="${POSTGRES_DB}" \
  --dry-run=client -o yaml | kubectl "${kubectl_args[@]}" apply -f -

value_args=()
if [[ -n "${FLOATING_IP}" ]]; then
  value_args+=(--set "minio.externalIP=${FLOATING_IP}" --set "mlflow.externalIP=${FLOATING_IP}" --set "gateway.externalIP=${FLOATING_IP}")
fi

helm "${helm_args[@]}" upgrade --install proj08-platform "${REPO_ROOT}/k8s/platform" \
  --namespace gourmetgram-platform \
  --create-namespace \
  "${value_args[@]}" \
  --wait \
  --timeout 10m

echo "Platform installed: MLflow on port 8000, MinIO console on port 9001."
