#!/usr/bin/env bash
set -euo pipefail

# Load the SmartCat FastAPI serving image and publish it to the in-cluster
# registry. The Kubernetes deployment pulls this image for /predict and
# /predict_batch traffic from Actual Budget.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_TAR="${SERVING_IMAGE_TAR:-${1:-${REPO_ROOT}/artifacts/docker/actualbudget-serving_latest-linux_amd64.tar.gz}}"
REGISTRY_HOST="${REGISTRY_HOST:-registry.kube-system.svc.cluster.local:5000}"
SOURCE_IMAGE="${SERVING_SOURCE_IMAGE:-actualbudget-serving:latest}"
TARGET_IMAGE="${SERVING_TARGET_IMAGE:-${REGISTRY_HOST}/actualbudget-serving:latest}"

if [[ ! -f "${IMAGE_TAR}" ]]; then
  cat >&2 <<MSG
SmartCat serving image tarball was not found:
  ${IMAGE_TAR}

Copy the tarball to node1, or set SERVING_IMAGE_TAR=/path/to/file.tar.gz.
MSG
  exit 1
fi

docker_cmd() {
  if docker info >/dev/null 2>&1; then
    docker "$@"
  else
    sudo docker "$@"
  fi
}

if command -v docker >/dev/null 2>&1; then
  docker_cmd load -i "${IMAGE_TAR}"
  docker_cmd tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"
  docker_cmd push "${TARGET_IMAGE}"
elif command -v ctr >/dev/null 2>&1; then
  tmp_tar="$(mktemp)"
  trap 'rm -f "${tmp_tar}"' EXIT
  gunzip -c "${IMAGE_TAR}" > "${tmp_tar}"
  sudo ctr -n k8s.io images import "${tmp_tar}"
  sudo ctr -n k8s.io images tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}" || true
  sudo ctr -n k8s.io images push --plain-http "${TARGET_IMAGE}"
else
  echo "Neither docker nor ctr is installed; cannot load/push ${IMAGE_TAR}." >&2
  exit 1
fi

echo "Published ${TARGET_IMAGE}."
