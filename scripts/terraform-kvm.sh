#!/usr/bin/env bash
set -euo pipefail

# Run Terraform with a clean OpenStack environment. Chameleon Jupyter injects
# OS_ACCESS_TOKEN and related OS_* variables, and those override clouds.yaml.
# This wrapper preserves only the normal shell variables Terraform needs and
# forces the OpenStack provider to use ~/.config/openstack/clouds.yaml:clouds.kvm.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${TF_DIR:-${REPO_ROOT}/tf/kvm}"
TERRAFORM_BIN="${TERRAFORM_BIN:-terraform}"
CLOUDS_FILE="${OS_CLIENT_CONFIG_FILE:-${HOME}/.config/openstack/clouds.yaml}"

if [[ ! -f "${CLOUDS_FILE}" ]]; then
  echo "Missing ${CLOUDS_FILE}. Run scripts/configure-kvm-clouds-yaml.sh first." >&2
  exit 1
fi

if ! command -v "${TERRAFORM_BIN}" >/dev/null 2>&1; then
  if [[ -x "${HOME}/.local/bin/terraform" ]]; then
    TERRAFORM_BIN="${HOME}/.local/bin/terraform"
  else
    echo "terraform not found. Run scripts/install-terraform.sh first." >&2
    exit 1
  fi
fi

cd "${TF_DIR}"

env -i \
  HOME="${HOME}" \
  USER="${USER:-}" \
  PATH="${PATH}" \
  TERM="${TERM:-xterm}" \
  OS_CLOUD="kvm" \
  OS_CLIENT_CONFIG_FILE="${CLOUDS_FILE}" \
  "${TERRAFORM_BIN}" "$@"
