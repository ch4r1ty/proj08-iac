#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: scripts/check-public-services.sh <floating-ip> [--open]

Checks public demo services. Add --open, or set OPEN_DEMO_PAGES=1, to open the
Actual app, SmartCat API docs, and project Grafana dashboards in the local
browser after the checks finish.
EOF
}

FLOATING_IP="${FLOATING_IP:-}"
OPEN_DEMO_PAGES="${OPEN_DEMO_PAGES:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open)
      OPEN_DEMO_PAGES=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${FLOATING_IP}" ]]; then
        FLOATING_IP="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
  shift
done

if [[ -z "${FLOATING_IP}" ]]; then
  usage
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

if [[ "${OPEN_DEMO_PAGES}" == "1" || "${OPEN_DEMO_PAGES}" == "true" ]]; then
  "${SCRIPT_DIR}/open-demo-pages.sh" "${FLOATING_IP}" || true
fi
