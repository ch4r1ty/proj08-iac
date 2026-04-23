#!/usr/bin/env bash
set -euo pipefail

# The KVM@TACC service catalog labels Nova/Neutron endpoints with region
# "KVM@TACC". If clouds.yaml says regionOne, catalog listing may work but
# compute/network operations such as keypair list and server create fail.

CLOUDS_FILE="${OS_CLIENT_CONFIG_FILE:-${HOME}/.config/openstack/clouds.yaml}"
if [[ ! -f "${CLOUDS_FILE}" ]]; then
  echo "Missing ${CLOUDS_FILE}. Run scripts/configure-kvm-clouds-yaml.sh first." >&2
  exit 1
fi

python3 - <<PY
from pathlib import Path
p = Path('${CLOUDS_FILE}')
s = p.read_text()
s = s.replace('region_name: "regionOne"', 'region_name: "KVM@TACC"')
s = s.replace('region_name: regionOne', 'region_name: "KVM@TACC"')
s = s.replace('auth_url: "https://kvm.tacc.chameleoncloud.org:5000/v3"', 'auth_url: "https://kvm.tacc.chameleoncloud.org:5000/v3"')
s = s.replace('auth_url: https://kvm.tacc.chameleoncloud.org:5000\n', 'auth_url: "https://kvm.tacc.chameleoncloud.org:5000/v3"\n')
p.write_text(s)
print(p)
PY

echo "Updated KVM clouds.yaml region to KVM@TACC."
