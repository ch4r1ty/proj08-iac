#!/usr/bin/env bash
set -euo pipefail

# Provision the 3-node KVM@TACC cluster with OpenStack CLI instead of Terraform.
# This bypasses a Terraform provider service-catalog issue while creating the
# same resources: private network, sharednet ports, public security group,
# three Ubuntu nodes, and a floating IP attached to node1.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OS_CMD=("${REPO_ROOT}/scripts/openstack-kvm.sh")
SUFFIX="${SUFFIX:-proj08}"
RESERVATION_ID="${RESERVATION_ID:-${1:-}}"
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}"
IMAGE_NAME="${IMAGE_NAME:-CC-Ubuntu24.04}"
SHARED_NET="${SHARED_NET:-sharednet1}"
PUBLIC_POOL="${PUBLIC_POOL:-public}"
PRIVATE_NET="private-net-mlops-${SUFFIX}"
PRIVATE_SUBNET="private-subnet-mlops-${SUFFIX}"
SECURITY_GROUP="proj08-public-services-${SUFFIX}"
CIDR="192.168.1.0/24"
PORTS=(22 80 443 3000 3001 5000 5006 8000 8888 9000 9001 9090 30080 30083 30090 30300 30443 30901 30909)

declare -A NODE_IPS=(
  [node1]="192.168.1.11"
  [node2]="192.168.1.12"
  [node3]="192.168.1.13"
)

if [[ -z "${RESERVATION_ID}" ]]; then
  echo "Usage: RESERVATION_ID=<reserved-flavor-id> $0" >&2
  echo "Example: RESERVATION_ID=3bb9f2d9-... $0" >&2
  exit 1
fi

run() {
  echo "+ openstack $*" >&2
  "${OS_CMD[@]}" "$@"
}

value() {
  "${OS_CMD[@]}" "$@" -f value 2>/dev/null || true
}

ensure_keypair() {
  if ! run keypair show "${KEY_NAME}" >/dev/null 2>&1; then
    echo "Keypair '${KEY_NAME}' was not found. Available keypairs:" >&2
    run keypair list >&2 || true
    echo "Set KEY_NAME=<existing-keypair> and rerun." >&2
    exit 1
  fi
}

ensure_networks() {
  if ! run network show "${PRIVATE_NET}" >/dev/null 2>&1; then
    run network create "${PRIVATE_NET}" --disable-port-security >/dev/null
  fi
  if ! run subnet show "${PRIVATE_SUBNET}" >/dev/null 2>&1; then
    run subnet create "${PRIVATE_SUBNET}" \
      --network "${PRIVATE_NET}" \
      --subnet-range "${CIDR}" \
      --no-gateway >/dev/null
  fi
}

ensure_security_group() {
  if ! run security group show "${SECURITY_GROUP}" >/dev/null 2>&1; then
    run security group create "${SECURITY_GROUP}" \
      --description "Browser and demo ports for proj08 Smart Transaction Categorization" >/dev/null
  fi

  for port in "${PORTS[@]}"; do
    run security group rule create "${SECURITY_GROUP}" \
      --ingress --ethertype IPv4 --protocol tcp --dst-port "${port}:${port}" --remote-ip 0.0.0.0/0 >/dev/null 2>&1 || true
  done
  run security group rule create "${SECURITY_GROUP}" \
    --ingress --ethertype IPv4 --protocol icmp --remote-ip 0.0.0.0/0 >/dev/null 2>&1 || true
}

ensure_port() {
  local name="$1"
  local network="$2"
  shift 2
  local port_id
  port_id="$(value port show "${name}" -c id)"
  if [[ -z "${port_id}" ]]; then
    run port create "${name}" --network "${network}" "$@" >/dev/null
    port_id="$(value port show "${name}" -c id)"
  fi
  printf '%s' "${port_id}"
}

ensure_server() {
  local node="$1"
  local private_ip="${NODE_IPS[${node}]}"
  local server_name="${node}-mlops-${SUFFIX}"
  local shared_port_name="sharednet1-${node}-mlops-${SUFFIX}"
  local private_port_name="port-${node}-mlops-${SUFFIX}"
  local shared_port_id private_port_id server_id user_data

  shared_port_id="$(ensure_port "${shared_port_name}" "${SHARED_NET}" --security-group "${SECURITY_GROUP}")"
  private_port_id="$(ensure_port "${private_port_name}" "${PRIVATE_NET}" --fixed-ip "subnet=${PRIVATE_SUBNET},ip-address=${private_ip}" --disable-port-security)"

  server_id="$(value server show "${server_name}" -c id)"
  if [[ -z "${server_id}" ]]; then
    user_data="$(mktemp)"
    cat > "${user_data}" <<USERDATA
#! /bin/bash
echo "127.0.1.1 ${server_name}" >> /etc/hosts
su cc -c /usr/local/bin/cc-load-public-keys
USERDATA
    run server create "${server_name}" \
      --image "${IMAGE_NAME}" \
      --flavor "${RESERVATION_ID}" \
      --key-name "${KEY_NAME}" \
      --nic "port-id=${shared_port_id}" \
      --nic "port-id=${private_port_id}" \
      --user-data "${user_data}" >/dev/null
    rm -f "${user_data}"
  fi

  run server show "${server_name}" -c id -c status -c addresses
  if [[ "${node}" == "node1" ]]; then
    echo "${shared_port_id}" > /tmp/proj08_node1_shared_port_id
  fi
}

ensure_floating_ip() {
  local node1_port_id fip existing
  node1_port_id="$(cat /tmp/proj08_node1_shared_port_id)"
  existing="$(value floating ip list --port "${node1_port_id}" -c 'Floating IP Address' | head -n 1)"
  if [[ -n "${existing}" ]]; then
    fip="${existing}"
  else
    fip="$(run floating ip create "${PUBLIC_POOL}" --port "${node1_port_id}" -f value -c floating_ip_address)"
  fi

  cat <<MSG

Provisioning complete.
floating_ip_out = "${fip}"
node1_sharednet_port_id = "${node1_port_id}"
public_service_ports = [${PORTS[*]}]

Next commands from your laptop:
  ssh -i ~/.ssh/id_rsa_chameleon cc@${fip}
MSG
}

ensure_keypair
ensure_networks
ensure_security_group
for node in node1 node2 node3; do
  ensure_server "${node}"
done
ensure_floating_ip
