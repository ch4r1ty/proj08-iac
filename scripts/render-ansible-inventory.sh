#!/usr/bin/env bash
set -euo pipefail

# Update the Ansible and Kubespray inventories when Terraform assigns a new
# node1 floating IP. Private node IPs stay on the Terraform/Kubespray defaults.

FLOATING_IP="${FLOATING_IP:-${1:-}}"
if [[ -z "${FLOATING_IP}" ]]; then
  echo "Usage: $0 <node1-floating-ip>" >&2
  exit 1
fi

files=(
  "ansible/inventory.yml"
  "ansible/ansible.cfg"
  "ansible/k8s/inventory/mycluster/hosts.yaml"
)

for file in "${files[@]}"; do
  if [[ -f "${file}" ]]; then
    perl -0pi -e 's/129\.114\.\d+\.\d+/'"${FLOATING_IP//./\\.}"'/g' "${file}"
  fi
done

echo "Updated Ansible inventory files to use node1 floating IP ${FLOATING_IP}."
