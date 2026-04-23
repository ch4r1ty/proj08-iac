#!/usr/bin/env bash
set -euo pipefail

# Terraform cannot authenticate with the short-lived Chameleon notebook SSO
# token. Use a KVM@TACC application credential instead and write it to
# ~/.config/openstack/clouds.yaml for the OpenStack Terraform provider.

CLOUD_NAME="${CLOUD_NAME:-kvm}"
CLOUDS_FILE="${CLOUDS_FILE:-${HOME}/.config/openstack/clouds.yaml}"
AUTH_URL="${AUTH_URL:-https://kvm.tacc.chameleoncloud.org:5000}"
REGION_NAME="${REGION_NAME:-KVM@TACC}"

mkdir -p "$(dirname "${CLOUDS_FILE}")"

cat <<'MSG'
Create a KVM@TACC application credential in Horizon first:
  Identity -> Application Credentials -> Create Application Credential
Use an expiration after the demo window, then copy the generated id and secret.
MSG

read -r -p "Application credential id: " APP_CRED_ID
read -r -s -p "Application credential secret: " APP_CRED_SECRET
printf '\n'

if [[ -z "${APP_CRED_ID}" || -z "${APP_CRED_SECRET}" ]]; then
  echo "Application credential id/secret cannot be empty." >&2
  exit 1
fi

umask 077
cat > "${CLOUDS_FILE}" <<YAML
clouds:
  ${CLOUD_NAME}:
    region_name: "${REGION_NAME}"
    interface: "public"
    identity_api_version: 3
    auth_type: "v3applicationcredential"
    auth:
      auth_url: "${AUTH_URL}"
      application_credential_id: "${APP_CRED_ID}"
      application_credential_secret: "${APP_CRED_SECRET}"
YAML

cat <<MSG
Wrote ${CLOUDS_FILE}
Now run:
  export OS_CLOUD=${CLOUD_NAME}
  unset OS_TOKEN OS_AUTH_TOKEN OS_ACCESS_TOKEN OS_AUTH_TYPE
  cd /work/proj08-iac/tf/kvm
  terraform apply -var suffix=proj08 -var reservation=<reserved-flavor-id>
MSG
