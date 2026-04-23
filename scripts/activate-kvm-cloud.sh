# Source this before running Terraform/OpenStack commands with the KVM@TACC
# application credential. Chameleon Jupyter exports OS_* variables for its own
# session, and those variables override clouds.yaml even when OS_CLOUD is set.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Run this with source, not bash:" >&2
  echo "  source scripts/activate-kvm-cloud.sh" >&2
  exit 1
fi

for name in $(env | awk -F= '/^OS_/ {print $1}'); do
  unset "${name}"
done

export OS_CLOUD="${OS_CLOUD_NAME:-kvm}"

echo "OpenStack CLI/Terraform will use clouds.yaml cloud: ${OS_CLOUD}"
echo "Verify with: openstack --os-cloud ${OS_CLOUD} catalog list"
