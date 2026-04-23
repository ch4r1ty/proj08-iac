#!/usr/bin/env bash
set -euo pipefail

# Install kube-prometheus-stack with Node Exporter, kube-state-metrics,
# Prometheus, Grafana, and project-specific alerts/ServiceMonitor objects.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-}"
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
  echo "helm is required for monitoring installation. Install Helm on node1 first." >&2
  exit 1
fi

helm "${helm_args[@]}" repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
helm "${helm_args[@]}" repo update
helm "${helm_args[@]}" upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values "${REPO_ROOT}/k8s/monitoring/kube-prometheus-stack-values.yaml" \
  --wait \
  --timeout 10m

kubectl "${kubectl_args[@]}" apply -f "${REPO_ROOT}/k8s/monitoring/smartcat-servicemonitor.yaml"
kubectl "${kubectl_args[@]}" apply -f "${REPO_ROOT}/k8s/monitoring/alert-rules.yaml"

echo "Monitoring installed: Grafana NodePort 30300, Prometheus NodePort 30909."
