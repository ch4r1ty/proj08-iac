# Leave provider configuration empty so Terraform can use the OpenStack
# credentials already present in the Chameleon Jupyter environment, including
# OS_AUTH_URL, OS_AUTH_TYPE, OS_ACCESS_TOKEN, OS_PROJECT_NAME, and OS_REGION_NAME.
# If a team member wants to use clouds.yaml instead, they can set OS_CLOUD in
# their shell without changing this file.
provider "openstack" {}
