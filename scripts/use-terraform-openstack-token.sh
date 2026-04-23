# Source this file in a Chameleon Jupyter terminal before running Terraform.
# Chameleon notebooks expose OS_ACCESS_TOKEN, while the Terraform OpenStack
# provider expects OS_TOKEN or OS_AUTH_TOKEN for token-based auth.

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

# The Terraform OpenStack provider does not understand Chameleon's notebook
# auth type string, so leave auth selection to OS_TOKEN/OS_AUTH_TOKEN.
unset OS_AUTH_TYPE

echo "Terraform OpenStack token auth is ready."
echo "Set: OS_TOKEN, OS_AUTH_TOKEN, OS_IDENTITY_API_VERSION=${OS_IDENTITY_API_VERSION}"
