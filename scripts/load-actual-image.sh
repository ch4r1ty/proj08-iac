#!/usr/bin/env bash
set -euo pipefail

# Load the built Actual Budget image tarball and publish it to the in-cluster
# registry used by the Kubernetes manifests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE_TAR="${IMAGE_TAR:-${1:-${REPO_ROOT}/actual-smartcat_actual-sync-serving-0343bdfcf-stable-linux_amd64(1).tar.gz}}"
SOURCE_IMAGE="${SOURCE_IMAGE:-actual-smartcat/actual-sync:serving-0343bdfcf-stable}"
TARGET_IMAGE="${TARGET_IMAGE:-10.233.51.71:5000/actual-sync:latest}"

if [[ ! -f "${IMAGE_TAR}" ]]; then
  cat >&2 <<MSG
Actual image tarball was not found:
  ${IMAGE_TAR}

Copy the tarball to node1, or set IMAGE_TAR=/path/to/file.tar.gz.
MSG
  exit 1
fi

if command -v docker >/dev/null 2>&1; then
  docker load -i "${IMAGE_TAR}"
  docker tag "${SOURCE_IMAGE}" "${TARGET_IMAGE}"
  docker push "${TARGET_IMAGE}"
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
