#!/usr/bin/env bash
set -euo pipefail

# Create the three-node Chameleon KVM cluster used by the proj08 demo.
# The notebook reserves capacity first, then this script uses the reserved
# flavor id to create the private network, ports, security group, servers,
# floating IP, and local inventory files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SUFFIX="${SUFFIX:-proj08}"
RESERVATION_ID="${RESERVED_FLAVOR_ID:-${RESERVATION_ID:-${1:-}}}"
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}"
LOG_DIR="${LOG_DIR:-${REPO_ROOT}/artifacts/chameleon}"
ENV_FILE="${ENV_FILE:-${LOG_DIR}/latest-cluster.env}"

usage() {
  cat <<EOF
Usage:
  RESERVATION_ID=<reserved-flavor-id> KEY_NAME=${KEY_NAME} $0
  KEY_NAME=${KEY_NAME} $0 <reserved-flavor-id>

The reserved flavor id comes from the Chameleon lease reservation notebook.
For example, the successful April 2026 run used:
  KEY_NAME=id_rsa_chameleon $0 3bb9f2d9-6dd7-4d87-ba7b-74cfb437af8b

This script expects ~/.config/openstack/clouds.yaml to contain a KVM@TACC
application credential. If it is missing, run:
  bash scripts/configure-kvm-clouds-yaml.sh
EOF
}

if [[ "${RESERVATION_ID}" == "--help" || "${RESERVATION_ID}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ -z "${RESERVATION_ID}" ]]; then
  usage >&2
  exit 1
fi

cd "${REPO_ROOT}"
mkdir -p "${LOG_DIR}"

if [[ ! -f "${HOME}/.config/openstack/clouds.yaml" ]]; then
  cat >&2 <<'MSG'
Missing ~/.config/openstack/clouds.yaml.
Create a KVM@TACC application credential in Horizon, then run:
  bash scripts/configure-kvm-clouds-yaml.sh
MSG
  exit 1
fi

# Chameleon notebooks often export short-lived OS_* variables from a different
# site. The wrapper ignores those variables and reads the KVM clouds.yaml.
"${SCRIPT_DIR}/fix-kvm-cloud-region.sh"

echo "Checking KVM@TACC OpenStack authentication..."
"${SCRIPT_DIR}/openstack-kvm.sh" token issue -f value -c id >/dev/null

echo "Checking keypair ${KEY_NAME}..."
if ! "${SCRIPT_DIR}/openstack-kvm.sh" keypair show "${KEY_NAME}" >/dev/null 2>&1; then
  echo "Keypair ${KEY_NAME} was not found. Available keypairs:" >&2
  "${SCRIPT_DIR}/openstack-kvm.sh" keypair list >&2 || true
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
provision_log="${LOG_DIR}/provision-${timestamp}.log"

echo "Provisioning Chameleon KVM resources. Log: ${provision_log}"
if ! SUFFIX="${SUFFIX}" KEY_NAME="${KEY_NAME}" RESERVATION_ID="${RESERVATION_ID}" \
  "${SCRIPT_DIR}/provision-kvm-openstack.sh" "${RESERVATION_ID}" 2>&1 | tee "${provision_log}"; then
  echo "Provisioning failed. See ${provision_log}" >&2
  exit 1
fi

floating_ip="$(awk -F'"' '/floating_ip_out/ {print $2}' "${provision_log}" | tail -n 1)"
node1_port_id="$(awk -F'"' '/node1_sharednet_port_id/ {print $2}' "${provision_log}" | tail -n 1)"

if [[ -z "${floating_ip}" ]]; then
  echo "Could not parse floating_ip_out from ${provision_log}" >&2
  exit 1
fi

# Keep the repo inventory aligned with the newly-created node1 floating IP.
"${SCRIPT_DIR}/render-ansible-inventory.sh" "${floating_ip}"

cat > "${ENV_FILE}" <<EOF
SUFFIX=${SUFFIX}
RESERVED_FLAVOR_ID=${RESERVATION_ID}
KEY_NAME=${KEY_NAME}
FLOATING_IP=${floating_ip}
NODE1_SHAREDNET_PORT_ID=${node1_port_id}
NODE1_PRIVATE_IP=192.168.1.11
NODE2_PRIVATE_IP=192.168.1.12
NODE3_PRIVATE_IP=192.168.1.13
PUBLIC_SERVICE_PORTS="22 80 443 3000 3001 5000 5006 8000 8888 9000 9001 9090 30080 30083 30090 30300 30443 30901 30909"
EOF

cat <<MSG

Cluster VM provisioning complete.
Saved environment file:
  ${ENV_FILE}

SSH to node1:
  ssh -i ~/.ssh/id_rsa_chameleon cc@${floating_ip}

After Kubespray installs Kubernetes, deploy the project stack on node1:
  cd /home/cc/proj08-iac
  export KUBECONFIG=/etc/kubernetes/admin.conf
  bash scripts/deploy-k8s-stack.sh ${floating_ip}

Demo URLs after deployment:
  Actual HTTPS:     https://${floating_ip}:30443
  SmartCat API:     http://${floating_ip}:30090/docs
  Grafana:          http://${floating_ip}:30300
  Prometheus:       http://${floating_ip}:30909
  MLflow:           http://${floating_ip}:8000
  MinIO console:    http://${floating_ip}:9001

Grafana login: admin / admin123
MinIO login:   your-access-key / PL89sTsyClxjtvQVxjN9
MSG
