# Source this file in a Chameleon Jupyter terminal before running Terraform.
# Chameleon notebooks expose OS_ACCESS_TOKEN, while the Terraform OpenStack
# provider expects OS_TOKEN or OS_AUTH_TOKEN for token-based auth.
#
# The project reserves KVM@TACC resources. Some Jupyter shells keep a UC auth
# URL in OS_AUTH_URL, which makes Keystone reject an otherwise valid KVM@TACC
# Fernet token. Point Terraform at KVM@TACC unless the caller overrides it.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Run this with source, not bash:" >&2
  echo "  source scripts/use-terraform-openstack-token.sh" >&2
  exit 1
fi

if [[ -z "${OS_ACCESS_TOKEN:-}" ]]; then
  echo "OS_ACCESS_TOKEN is not set. Run the Chameleon notebook/context setup first." >&2
  return 1
fi

export OS_TOKEN="${OS_ACCESS_TOKEN}"
export OS_AUTH_TOKEN="${OS_ACCESS_TOKEN}"
export OS_IDENTITY_API_VERSION="${OS_IDENTITY_API_VERSION:-3}"
export OS_INTERFACE="${OS_INTERFACE:-public}"
export OS_REGION_NAME="${OS_REGION_NAME:-regionOne}"

# KVM@TACC is the correct OpenStack cloud for m1.large VM leases.
export OS_AUTH_URL="${TERRAFORM_OS_AUTH_URL:-https://kvm.tacc.chameleoncloud.org:5000/v3}"

# The Terraform OpenStack provider does not understand Chameleon's notebook
# auth type string, so leave auth selection to OS_TOKEN/OS_AUTH_TOKEN.
unset OS_AUTH_TYPE

cat <<MSG
Terraform OpenStack token auth is ready.
  OS_AUTH_URL=${OS_AUTH_URL}
  OS_TOKEN=<set>
  OS_AUTH_TOKEN=<set>
  OS_IDENTITY_API_VERSION=${OS_IDENTITY_API_VERSION}
MSG
