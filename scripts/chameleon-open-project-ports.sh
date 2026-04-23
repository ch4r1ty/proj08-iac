#!/usr/bin/env bash
set -euo pipefail

# Optional helper for existing clusters. It creates a single Chameleon security
# group containing all browser/demo ports and attaches it to node1's Neutron port.

SECURITY_GROUP="${SECURITY_GROUP:-proj08-public-services}"
PORT_ID="${PORT_ID:-${1:-}}"
PORTS=(22 80 443 3000 3001 5000 5006 8000 8888 9000 9001 9090 30080 30083 30090 30300 30443 30901 30909)

if [[ -z "${PORT_ID}" ]]; then
  echo "Usage: PORT_ID=<node1-sharednet-port-id> $0" >&2
  exit 1
fi

if ! command -v openstack >/dev/null 2>&1; then
  echo "openstack CLI not found. Source the Chameleon OpenStack RC file first." >&2
  exit 1
fi

if ! openstack security group show "${SECURITY_GROUP}" >/dev/null 2>&1; then
  openstack security group create "${SECURITY_GROUP}" --description "proj08 public browser/demo ports"
fi

for port in "${PORTS[@]}"; do
  openstack security group rule create "${SECURITY_GROUP}" \
    --ingress --ethertype IPv4 --protocol tcp --dst-port "${port}:${port}" --remote-ip 0.0.0.0/0 || true
done
openstack security group rule create "${SECURITY_GROUP}" \
  --ingress --ethertype IPv4 --protocol icmp --remote-ip 0.0.0.0/0 || true

openstack port set --security-group "${SECURITY_GROUP}" "${PORT_ID}"
echo "Attached ${SECURITY_GROUP} to ${PORT_ID}."
