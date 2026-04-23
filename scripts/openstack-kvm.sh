#!/usr/bin/env bash
set -euo pipefail

# Run OpenStack CLI with the same clean KVM clouds.yaml environment used by
# Terraform, avoiding notebook-provided OS_ACCESS_TOKEN overrides.

CLOUDS_FILE="${OS_CLIENT_CONFIG_FILE:-${HOME}/.config/openstack/clouds.yaml}"
if [[ ! -f "${CLOUDS_FILE}" ]]; then
  echo "Missing ${CLOUDS_FILE}. Run scripts/configure-kvm-clouds-yaml.sh first." >&2
  exit 1
fi

env -i \
  HOME="${HOME}" \
  USER="${USER:-}" \
  PATH="${PATH}" \
  TERM="${TERM:-xterm}" \
  OS_CLOUD="kvm" \
  OS_CLIENT_CONFIG_FILE="${CLOUDS_FILE}" \
  openstack "$@"
