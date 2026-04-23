#!/usr/bin/env bash
set -euo pipefail

# Diagnose the OpenStack authentication setup needed by Terraform on Chameleon.
# Terraform reads tf/kvm/clouds.yaml, ~/.config/openstack/clouds.yaml, or OS_* env vars.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cat <<'MSG'
Checking OpenStack auth sources for Terraform...
MSG

if [[ -f "${ROOT}/tf/kvm/clouds.yaml" ]]; then
  echo "[ok] Found repo-local ${ROOT}/tf/kvm/clouds.yaml"
fi

if [[ -f "${HOME}/.config/openstack/clouds.yaml" ]]; then
  echo "[ok] Found ${HOME}/.config/openstack/clouds.yaml"
fi

if env | grep -q '^OS_AUTH_URL='; then
  echo "[ok] OS_* OpenStack environment variables are present"
  env | grep '^OS_' | sed 's/=.*/=<set>/' | sort
else
  echo "[warn] No OS_* OpenStack environment variables found in this shell"
fi

found_any=0
for dir in "${HOME}" /work /etc /opt; do
  [[ -d "${dir}" ]] || continue
  while IFS= read -r file; do
    found_any=1
    echo "[candidate] ${file}"
  done < <(find "${dir}" -maxdepth 4 \( -name 'clouds.yaml' -o -name 'clouds.yml' -o -name '*openrc*' -o -name '*OpenRC*' \) 2>/dev/null | sort)
done

if [[ "${found_any}" == 0 ]]; then
  cat <<'MSG'
[warn] No clouds.yaml/openrc candidate was found.
Download an OpenStack RC file or clouds.yaml from Chameleon Horizon, then either:
  source <openrc-file>
or copy clouds.yaml to:
  ~/.config/openstack/clouds.yaml
or:
  proj08-iac/tf/kvm/clouds.yaml
MSG
fi
