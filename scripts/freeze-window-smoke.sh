#!/usr/bin/env bash
set -euo pipefail

FLOATING_IP="${FLOATING_IP:-129.114.26.122}"
INTERVAL_SECONDS=60
ITERATIONS=1
WITH_FEEDBACK=true
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin123}"
SMARTCAT_TRAFFIC_SOURCE="${SMARTCAT_TRAFFIC_SOURCE:-smoke}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/freeze-window-smoke.sh [options]

Options:
  --floating-ip IP       Public floating IP. Default: FLOATING_IP env or 129.114.26.122.
  --interval SECONDS     Sleep between loop iterations. Default: 60.
  --iterations N         Number of iterations. Use 0 for forever. Default: 1.
  --loop                 Run forever. Equivalent to --iterations 0.
  --no-feedback          Do not post synthetic feedback to SmartCat.
  SMARTCAT_TRAFFIC_SOURCE  Header value sent to SmartCat to mark smoke traffic. Default: smoke.
  -h, --help             Show this help.

Examples:
  bash scripts/freeze-window-smoke.sh
  bash scripts/freeze-window-smoke.sh --iterations 10 --interval 30
  bash scripts/freeze-window-smoke.sh --loop

The script is intentionally safe for the freeze window: it does not SSH into the
cluster, mutate Kubernetes resources, or touch Actual's SQLite budgets. It only
uses public HTTP(S) endpoints and optional SmartCat feedback events.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --floating-ip)
      FLOATING_IP="$2"
      shift 2
      ;;
    --interval)
      INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --loop)
      ITERATIONS=0
      shift
      ;;
    --no-feedback)
      WITH_FEEDBACK=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

ACTUAL_HTTPS="https://${FLOATING_IP}:30443"
ACTUAL_HEALTH="http://${FLOATING_IP}:30083/health"
SMARTCAT_BASE="http://${FLOATING_IP}:30090"
PROMETHEUS_BASE="http://${FLOATING_IP}:30909"
GRAFANA_BASE="http://${FLOATING_IP}:30300"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_command curl

if ! command -v python3 >/dev/null 2>&1 && [[ "${WITH_FEEDBACK}" == true ]]; then
  echo "python3 not found; disabling feedback event generation." >&2
  WITH_FEEDBACK=false
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

ok() {
  printf '[ok]   %s\n' "$1"
}

warn() {
  printf '[warn] %s\n' "$1"
}

check_get() {
  local name="$1"
  local url="$2"
  local code
  if (($# > 2)); then
    code="$(curl -k -sS --max-time 10 -o /dev/null -w '%{http_code}' "${@:3}" "${url}" || true)"
  else
    code="$(curl -k -sS --max-time 10 -o /dev/null -w '%{http_code}' "${url}" || true)"
  fi
  if [[ "${code}" =~ ^[23] ]]; then
    ok "${name} ${code}"
    return 0
  fi
  warn "${name} ${code:-curl_failed}"
  return 1
}

check_post_json() {
  local name="$1"
  local url="$2"
  local body="$3"
  local output="$4"
  local code
  code="$(curl -sS --max-time 15 -o "${output}" -w '%{http_code}' \
    -H 'Content-Type: application/json' \
    -H "X-Actual-Traffic-Source: ${SMARTCAT_TRAFFIC_SOURCE}" \
    -d "${body}" \
    "${url}" || true)"
  if [[ "${code}" =~ ^[23] ]]; then
    ok "${name} ${code}"
    return 0
  fi
  warn "${name} ${code:-curl_failed}"
  sed -n '1,5p' "${output}" 2>/dev/null || true
  return 1
}

prom_query() {
  local name="$1"
  local query="$2"
  local output="${TMP_DIR}/prom-${name// /_}.json"
  local code
  code="$(curl -sS --max-time 10 -G -o "${output}" -w '%{http_code}' \
    --data-urlencode "query=${query}" \
    "${PROMETHEUS_BASE}/api/v1/query" || true)"
  if [[ "${code}" =~ ^[23] ]] && grep -q '"status":"success"' "${output}"; then
    ok "Prometheus ${name}"
    sed -n '1,1p' "${output}"
    return 0
  fi
  warn "Prometheus ${name} ${code:-curl_failed}"
  sed -n '1,3p' "${output}" 2>/dev/null || true
  return 1
}

post_feedback_from_prediction() {
  local prediction_file="$1"
  local feedback_file="${TMP_DIR}/feedback.json"
  local feedback_body

  feedback_body="$(python3 - "${prediction_file}" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
top = payload.get("top_categories") or []
candidates = [item.get("category_id") for item in top if item.get("category_id")]
if not candidates:
    raise SystemExit(1)
print(json.dumps({
    "transaction_id": "freeze-smoke",
    "model_version": payload.get("model_version", "unknown"),
    "predicted_category_id": payload.get("predicted_category_id", candidates[0]),
    "applied_category_id": candidates[0],
    "confidence": payload.get("confidence"),
    "candidate_category_ids": candidates,
}))
PY
)"

  check_post_json "SmartCat feedback" "${SMARTCAT_BASE}/feedback" "${feedback_body}" "${feedback_file}"
}

run_once() {
  local failed=0
  local predict_file="${TMP_DIR}/predict.json"
  local batch_file="${TMP_DIR}/predict_batch.json"

  echo
  echo "=== $(date -u '+%Y-%m-%dT%H:%M:%SZ') ${FLOATING_IP} ==="

  check_get "Actual HTTPS" "${ACTUAL_HTTPS}" || failed=1
  check_get "Actual health" "${ACTUAL_HEALTH}" || failed=1
  check_get "SmartCat health" "${SMARTCAT_BASE}/healthz" || failed=1
  check_get "SmartCat docs" "${SMARTCAT_BASE}/docs" || failed=1
  check_get "Grafana health" "${GRAFANA_BASE}/api/health" -u "${GRAFANA_USER}:${GRAFANA_PASSWORD}" || failed=1
  check_get "Prometheus health" "${PROMETHEUS_BASE}/-/healthy" || failed=1

  check_post_json \
    "SmartCat predict" \
    "${SMARTCAT_BASE}/predict" \
    '{"transaction_description":"STARBUCKS STORE 1458 NEW YORK NY","country":"US","currency":"USD","amount":5.75}' \
    "${predict_file}" || failed=1

  check_post_json \
    "SmartCat predict_batch" \
    "${SMARTCAT_BASE}/predict_batch" \
    '{"items":[{"transaction_description":"UBER TRIP HELP.UBER.COM","country":"US","currency":"USD","amount":18.2},{"transaction_description":"COMCAST CABLE AUTOPAY","country":"US","currency":"USD","amount":92.0}]}' \
    "${batch_file}" || failed=1

  if [[ "${WITH_FEEDBACK}" == true && -s "${predict_file}" ]]; then
    post_feedback_from_prediction "${predict_file}" || failed=1
  fi

  check_get "SmartCat monitor" "${SMARTCAT_BASE}/monitor/summary" || failed=1
  check_get "SmartCat decision" "${SMARTCAT_BASE}/monitor/decision" || failed=1
  prom_query "smartcat up" 'up{job="smartcat-serving"}' || failed=1
  prom_query "request rate" 'smartcat:request_rate_5m' || true
  prom_query "p95 latency" 'smartcat:p95_latency_ms_5m' || true
  prom_query "feedback count" 'sum(increase(feedback_total[1h]))' || true

  return "${failed}"
}

iteration=0
overall_failed=0
while true; do
  iteration=$((iteration + 1))
  if ! run_once; then
    overall_failed=1
  fi

  if [[ "${ITERATIONS}" != "0" && "${iteration}" -ge "${ITERATIONS}" ]]; then
    break
  fi
  sleep "${INTERVAL_SECONDS}"
done

exit "${overall_failed}"
