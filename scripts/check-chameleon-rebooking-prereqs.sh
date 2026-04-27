#!/usr/bin/env bash
set -euo pipefail

# Non-destructive preflight for the Chameleon rebooking path.
# It checks local/Jupyter tooling and credentials without creating leases,
# instances, floating IPs, ports, networks, or security groups.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CLOUDS_FILE="${OS_CLIENT_CONFIG_FILE:-${HOME}/.config/openstack/clouds.yaml}"
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}"
IMAGE_NAME="${IMAGE_NAME:-CC-Ubuntu24.04}"
FLAVOR_NAME="${FLAVOR_NAME:-m1.large}"
SHARED_NET="${SHARED_NET:-sharednet1}"
RESERVATION_ENV="${RESERVATION_ENV:-${REPO_ROOT}/.proj08-reservation.env}"

status=0

ok() {
  printf '[ok] %s\n' "$*"
}

warn() {
  printf '[warn] %s\n' "$*"
}

fail() {
  printf '[fail] %s\n' "$*"
  status=1
}

have_command() {
  command -v "$1" >/dev/null 2>&1
}

cat <<MSG
Chameleon rebooking preflight
Repository: ${REPO_ROOT}
Clouds file: ${CLOUDS_FILE}
Keypair: ${KEY_NAME}
Image: ${IMAGE_NAME}
Flavor: ${FLAVOR_NAME}
Shared network: ${SHARED_NET}

MSG

if have_command python3; then
  ok "python3 is available: $(command -v python3)"
  if python3 - <<'PY' >/dev/null 2>&1
import importlib.util
raise SystemExit(0 if importlib.util.find_spec("chi") else 1)
PY
  then
    ok "python package 'chi' is importable"
  else
    warn "python package 'chi' is not importable; lease creation must run in Chameleon Jupyter or an environment with python-chi"
  fi
else
  fail "python3 is missing"
fi

if have_command openstack; then
  ok "openstack CLI is available: $(command -v openstack)"
else
  warn "openstack CLI is missing; VM provisioning cannot run from this shell"
fi

if [[ -f "${CLOUDS_FILE}" ]]; then
  ok "found clouds.yaml"
  if [[ "$(stat -f '%Lp' "${CLOUDS_FILE}" 2>/dev/null || stat -c '%a' "${CLOUDS_FILE}" 2>/dev/null || echo 600)" -gt 600 ]]; then
    warn "clouds.yaml permissions are broader than 600; consider chmod 600 ${CLOUDS_FILE}"
  fi
else
  warn "missing clouds.yaml; create a KVM@TACC application credential and run scripts/configure-kvm-clouds-yaml.sh"
fi

if [[ ! -x "${SCRIPT_DIR}/openstack-kvm.sh" ]]; then
  fail "missing executable scripts/openstack-kvm.sh"
fi

if have_command openstack && [[ -f "${CLOUDS_FILE}" ]]; then
  if "${SCRIPT_DIR}/openstack-kvm.sh" token issue -f value -c id >/dev/null 2>&1; then
    ok "KVM@TACC token issue succeeds"
  else
    fail "KVM@TACC token issue failed; check application credential id/secret, auth_url, region_name"
  fi

  if "${SCRIPT_DIR}/openstack-kvm.sh" keypair show "${KEY_NAME}" >/dev/null 2>&1; then
    ok "OpenStack keypair exists: ${KEY_NAME}"
  else
    fail "OpenStack keypair not found: ${KEY_NAME}"
    warn "available keypairs:"
    "${SCRIPT_DIR}/openstack-kvm.sh" keypair list || true
  fi

  if "${SCRIPT_DIR}/openstack-kvm.sh" network show "${SHARED_NET}" >/dev/null 2>&1; then
    ok "shared network exists: ${SHARED_NET}"
  else
    fail "shared network not found: ${SHARED_NET}"
  fi

  if "${SCRIPT_DIR}/openstack-kvm.sh" image show "${IMAGE_NAME}" >/dev/null 2>&1; then
    ok "image exists: ${IMAGE_NAME}"
  else
    fail "image not found: ${IMAGE_NAME}"
  fi

  if "${SCRIPT_DIR}/openstack-kvm.sh" flavor list -f value -c Name | grep -qx "${FLAVOR_NAME}"; then
    ok "base flavor is visible: ${FLAVOR_NAME}"
  else
    warn "base flavor ${FLAVOR_NAME} is not visible; this may be normal if only reserved flavors are exposed in the current context"
  fi

  if [[ -f "${RESERVATION_ENV}" ]]; then
    reserved_flavor_id="$(awk -F= '/^RESERVED_FLAVOR_ID=/ {print $2}' "${RESERVATION_ENV}" | tail -n 1)"
    if [[ -n "${reserved_flavor_id}" ]]; then
      if "${SCRIPT_DIR}/openstack-kvm.sh" flavor show "${reserved_flavor_id}" >/dev/null 2>&1; then
        ok "reserved flavor id from ${RESERVATION_ENV} is visible: ${reserved_flavor_id}"
      else
        warn "reserved flavor id from ${RESERVATION_ENV} is not visible yet: ${reserved_flavor_id}"
      fi
    else
      warn "${RESERVATION_ENV} exists but has no RESERVED_FLAVOR_ID"
    fi
  else
    warn "no reservation env found at ${RESERVATION_ENV}; create/reuse a lease first if you are about to provision VMs"
  fi
else
  warn "skipping OpenStack live checks because CLI or clouds.yaml is unavailable"
fi

cat <<'MSG'

This preflight does not reserve or create anything.
For the full flow, use docs/chameleon-rebooking-runbook.md.
MSG

exit "${status}"
