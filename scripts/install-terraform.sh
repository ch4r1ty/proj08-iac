#!/usr/bin/env bash
set -euo pipefail

# Install Terraform into ~/.local/bin for Chameleon Jupyter, Linux VMs, or a
# developer laptop. The script auto-detects OS/CPU unless OS or ARCH is set.

TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.14.4}"
INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"

raw_os="${OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
raw_arch="${ARCH:-$(uname -m)}"
case "${raw_os}" in
  linux|darwin) OS="${raw_os}" ;;
  *) echo "Unsupported OS: ${raw_os}" >&2; exit 1 ;;
esac
case "${raw_arch}" in
  x86_64|amd64) ARCH="amd64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: ${raw_arch}" >&2; exit 1 ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

mkdir -p "${INSTALL_DIR}"
url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_${OS}_${ARCH}.zip"

echo "Downloading ${url}"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${url}" -o "${TMP_DIR}/terraform.zip"
elif command -v wget >/dev/null 2>&1; then
  wget -q "${url}" -O "${TMP_DIR}/terraform.zip"
else
  echo "curl or wget is required to download Terraform." >&2
  exit 1
fi

python3 - <<PY
import zipfile
zipfile.ZipFile('${TMP_DIR}/terraform.zip').extractall('${TMP_DIR}')
PY

install -m 0755 "${TMP_DIR}/terraform" "${INSTALL_DIR}/terraform"

cat <<MSG
Terraform installed at ${INSTALL_DIR}/terraform
Run this if terraform is not found in your current shell:
  export PATH="${INSTALL_DIR}:\$PATH"
MSG

"${INSTALL_DIR}/terraform" version
