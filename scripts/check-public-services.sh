#!/usr/bin/env bash
set -euo pipefail

FLOATING_IP="${FLOATING_IP:-${1:-}}"
if [[ -z "${FLOATING_IP}" ]]; then
  echo "Usage: $0 <floating-ip>" >&2
  exit 1
fi

check() {
  local name="$1"
  local url="$2"
  if curl -kfsS --max-time 8 -I "${url}" >/dev/null 2>&1 || curl -kfsS --max-time 8 "${url}" >/dev/null 2>&1; then
    printf '[ok]   %-24s %s\n' "${name}" "${url}"
  else
    printf '[warn] %-24s %s\n' "${name}" "${url}"
  fi
}

check "Actual HTTPS" "https://${FLOATING_IP}:30443"
check "Actual HTTP fallback" "http://${FLOATING_IP}:30083/health"
check "SmartCat health" "http://${FLOATING_IP}:30090/healthz"
check "SmartCat docs" "http://${FLOATING_IP}:30090/docs"
check "Grafana" "http://${FLOATING_IP}:30300/login"
check "Prometheus" "http://${FLOATING_IP}:30909/-/ready"
check "MLflow" "http://${FLOATING_IP}:8000"
check "MinIO console" "http://${FLOATING_IP}:9001"
