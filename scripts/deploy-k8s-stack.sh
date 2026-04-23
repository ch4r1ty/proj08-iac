#!/usr/bin/env bash
set -euo pipefail

# One-command deployment for an already bootstrapped Kubespray cluster. Run on
# node1 after /etc/kubernetes/admin.conf and the internal registry are ready.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLOATING_IP="${FLOATING_IP:-${1:-}}"
IMAGE_TAR="${IMAGE_TAR:-}"

if [[ -z "${FLOATING_IP}" ]]; then
  echo "Usage: FLOATING_IP=<node1-floating-ip> $0" >&2
  echo "Example: FLOATING_IP=129.114.26.190 $0" >&2
  exit 1
fi

export KUBECONFIG="${KUBECONFIG:-/etc/kubernetes/admin.conf}"

if [[ -n "${IMAGE_TAR}" || -f "${REPO_ROOT}/actual-smartcat_actual-sync-serving-0343bdfcf-stable-linux_amd64(1).tar.gz" ]]; then
  "${SCRIPT_DIR}/load-actual-image.sh" "${IMAGE_TAR:-${REPO_ROOT}/actual-smartcat_actual-sync-serving-0343bdfcf-stable-linux_amd64(1).tar.gz}"
else
  echo "Skipping Actual image load because no IMAGE_TAR was provided. The registry must already contain 10.233.51.71:5000/actual-sync:latest."
fi

"${SCRIPT_DIR}/install-platform.sh" "${FLOATING_IP}"
"${SCRIPT_DIR}/install-monitoring.sh"
"${SCRIPT_DIR}/setup-actual-https.sh" "${FLOATING_IP}"
"${SCRIPT_DIR}/check-public-services.sh" "${FLOATING_IP}" || true
