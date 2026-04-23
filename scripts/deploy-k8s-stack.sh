#!/usr/bin/env bash
set -euo pipefail

# One-command deployment for an already bootstrapped Kubespray cluster. Run on
# node1 after /etc/kubernetes/admin.conf and the internal registry are ready.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLOATING_IP="${FLOATING_IP:-${1:-}}"
IMAGE_TAR="${IMAGE_TAR:-}"
SERVING_IMAGE_TAR="${SERVING_IMAGE_TAR:-}"
REGISTRY_HOST="${REGISTRY_HOST:-registry.kube-system.svc.cluster.local:5000}"

if [[ -z "${FLOATING_IP}" ]]; then
  echo "Usage: FLOATING_IP=<node1-floating-ip> $0" >&2
  echo "Example: FLOATING_IP=129.114.26.190 $0" >&2
  exit 1
fi

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

ACTUAL_IMAGE_TAR_CANDIDATE="${IMAGE_TAR:-$(ls -t "${REPO_ROOT}"/artifacts/docker/actual-smartcat_actual-sync-serving-*-linux_amd64.tar.gz 2>/dev/null | head -n 1 || true)}"
if [[ -n "${ACTUAL_IMAGE_TAR_CANDIDATE}" ]]; then
  REGISTRY_HOST="${REGISTRY_HOST}" "${SCRIPT_DIR}/load-actual-image.sh" "${ACTUAL_IMAGE_TAR_CANDIDATE}"
else
  echo "Skipping Actual image load because no IMAGE_TAR was provided. The registry must already contain ${REGISTRY_HOST}/actual-sync:latest."
fi

if [[ -n "${SERVING_IMAGE_TAR}" || -f "${REPO_ROOT}/artifacts/docker/actualbudget-serving_latest-linux_amd64.tar.gz" ]]; then
  REGISTRY_HOST="${REGISTRY_HOST}" "${SCRIPT_DIR}/load-serving-image.sh" "${SERVING_IMAGE_TAR:-${REPO_ROOT}/artifacts/docker/actualbudget-serving_latest-linux_amd64.tar.gz}"
else
  echo "Skipping SmartCat serving image load because no SERVING_IMAGE_TAR was provided. The registry must already contain ${REGISTRY_HOST}/actualbudget-serving:latest."
fi

"${SCRIPT_DIR}/install-platform.sh" "${FLOATING_IP}"
"${SCRIPT_DIR}/install-monitoring.sh"
"${SCRIPT_DIR}/setup-actual-https.sh" "${FLOATING_IP}"
"${SCRIPT_DIR}/check-public-services.sh" "${FLOATING_IP}" || true
