#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/open-demo-pages.sh <floating-ip> [--dry-run]

Opens the project demo pages in the local desktop browser. Run this from a
laptop/workstation after the Chameleon services are reachable.

Environment:
  FLOATING_IP   Public floating IP, used when the first argument is omitted.
  GRAFANA_URL   Override Grafana base URL. Default: http://<floating-ip>:30300
  DRY_RUN=1     Print URLs without opening a browser.
EOF
}

FLOATING_IP="${FLOATING_IP:-}"
DRY_RUN="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
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

GRAFANA_BASE="${GRAFANA_URL:-http://${FLOATING_IP}:30300}"

URLS=(
  "Actual Budget|https://${FLOATING_IP}:30443"
  "SmartCat API docs|http://${FLOATING_IP}:30090/docs"
  "Grafana Traffic Control|${GRAFANA_BASE}/d/actual-ml-traffic-control/smartcat-traffic-control?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s"
  "Grafana System Overview|${GRAFANA_BASE}/d/actual-ml-system-overview/actual-ml-system-overview?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s"
  "Grafana Model Behavior|${GRAFANA_BASE}/d/actual-ml-model-behavior/model-behavior?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s"
  "Grafana Data and Rollout|${GRAFANA_BASE}/d/actual-ml-data-rollout/data-quality-and-rollout?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s"
  "Prometheus Targets|http://${FLOATING_IP}:30909/targets"
  "MLflow Experiments|http://${FLOATING_IP}:8000"
)

open_url() {
  local url="$1"
  if [[ "${DRY_RUN}" == "1" || "${DRY_RUN}" == "true" ]]; then
    return 0
  fi

  if command -v open >/dev/null 2>&1; then
    open "${url}" >/dev/null 2>&1
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${url}" >/dev/null 2>&1
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe Start-Process "${url}" >/dev/null 2>&1
  else
    return 1
  fi
}

echo "Demo pages:"
for entry in "${URLS[@]}"; do
  label="${entry%%|*}"
  url="${entry#*|}"
  printf '  %-24s %s\n' "${label}" "${url}"
done

if [[ "${DRY_RUN}" == "1" || "${DRY_RUN}" == "true" ]]; then
  exit 0
fi

echo "Opening demo pages in the local browser..."
failed=0
for entry in "${URLS[@]}"; do
  url="${entry#*|}"
  if ! open_url "${url}"; then
    failed=1
  fi
  sleep 0.2
done

if [[ "${failed}" == "1" ]]; then
  echo "No desktop opener was available here. Use the printed URLs above." >&2
fi
