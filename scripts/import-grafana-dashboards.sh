#!/usr/bin/env bash
set -euo pipefail

# Import standard Grafana dashboards into the project Grafana instance.
# This is useful after a fresh Chameleon/Kubernetes deployment because the
# kube-prometheus-stack service starts with datasources but not the extra
# classroom/demo dashboards the team wants to show.

GRAFANA_URL="${GRAFANA_URL:-${1:-http://129.114.26.122:30300}}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-admin123}"
PROMETHEUS_UID="${PROMETHEUS_UID:-prometheus}"
DASHBOARD_IDS="${DASHBOARD_IDS-1860 3119 15760}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_DASHBOARD_DIR="${LOCAL_DASHBOARD_DIR:-${REPO_ROOT}/k8s/monitoring/grafana-dashboards}"

python3 - <<PY
import base64
import json
import os
from pathlib import Path
import ssl
import sys
import urllib.error
import urllib.request

grafana_url = os.environ.get("GRAFANA_URL", "${GRAFANA_URL}").rstrip("/")
grafana_user = os.environ.get("GRAFANA_USER", "${GRAFANA_USER}")
grafana_password = os.environ.get("GRAFANA_PASSWORD", "${GRAFANA_PASSWORD}")
prometheus_uid = os.environ.get("PROMETHEUS_UID", "${PROMETHEUS_UID}")
dashboard_ids = os.environ.get("DASHBOARD_IDS", "${DASHBOARD_IDS}").split()
local_dashboard_dir = Path(os.environ.get("LOCAL_DASHBOARD_DIR", "${LOCAL_DASHBOARD_DIR}"))

credentials = base64.b64encode(f"{grafana_user}:{grafana_password}".encode()).decode()


def request_json(url, *, data=None, method="GET"):
    headers = {
        "Accept": "application/json",
        "Authorization": f"Basic {credentials}",
    }
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=60) as response:
        body = response.read().decode()
    return json.loads(body) if body else {}


def download_dashboard(dashboard_id):
    url = f"https://grafana.com/api/dashboards/{dashboard_id}/revisions/latest/download"
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return json.loads(response.read().decode())
    except urllib.error.URLError as exc:
        # Some Chameleon/Jupyter or local Python installs do not have an up to
        # date CA bundle. Fall back only for downloading public dashboard JSON.
        print(f"Verified TLS download failed for dashboard {dashboard_id}: {exc}", file=sys.stderr)
        print("Retrying dashboard download without certificate verification.", file=sys.stderr)
        context = ssl._create_unverified_context()
        with urllib.request.urlopen(url, timeout=60, context=context) as response:
            return json.loads(response.read().decode())


def datasource_inputs(dashboard):
    inputs = []
    for item in dashboard.get("__inputs", []):
        if item.get("type") == "datasource":
            inputs.append({
                "name": item["name"],
                "type": "datasource",
                "pluginId": item.get("pluginId", "prometheus"),
                "value": prometheus_uid,
            })
    if not inputs:
        # Some community dashboards use templating instead of __inputs. Keeping
        # this fallback makes the import idempotent for the common Prometheus
        # dashboards used in the course labs.
        inputs.append({
            "name": "DS_PROMETHEUS",
            "type": "datasource",
            "pluginId": "prometheus",
            "value": prometheus_uid,
        })
    return inputs


try:
    health = request_json(f"{grafana_url}/api/health")
    print(f"Grafana health: {health.get('database', 'unknown')} at {grafana_url}")
except Exception as exc:
    print(f"Could not reach Grafana at {grafana_url}: {exc}", file=sys.stderr)
    raise

for dashboard_id in dashboard_ids:
    dashboard = download_dashboard(dashboard_id)
    # Grafana requires id=None when overwriting imported dashboards by uid/title.
    dashboard["id"] = None
    payload = json.dumps({
        "dashboard": dashboard,
        "overwrite": True,
        "folderId": 0,
        "inputs": datasource_inputs(dashboard),
    }).encode()
    try:
        result = request_json(
            f"{grafana_url}/api/dashboards/import",
            data=payload,
            method="POST",
        )
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode()
        print(f"Dashboard {dashboard_id} import failed: {exc.code} {error_body}", file=sys.stderr)
        raise
    print(f"Dashboard {dashboard_id}: {result.get('status', 'ok')} {result.get('url', '')}")

if local_dashboard_dir.exists():
    for dashboard_path in sorted(local_dashboard_dir.glob("*.json")):
        dashboard = json.loads(dashboard_path.read_text())
        dashboard["id"] = None
        payload = json.dumps({
            "dashboard": dashboard,
            "overwrite": True,
            "folderId": 0,
        }).encode()
        try:
            result = request_json(
                f"{grafana_url}/api/dashboards/db",
                data=payload,
                method="POST",
            )
        except urllib.error.HTTPError as exc:
            error_body = exc.read().decode()
            if exc.code == 400 and "Cannot save provisioned dashboard" in error_body:
                print(f"Project dashboard {dashboard.get('title', dashboard_path.name)}: already provisioned by Grafana sidecar")
                continue
            print(f"Project dashboard {dashboard_path.name} import failed: {exc.code} {error_body}", file=sys.stderr)
            raise
        print(f"Project dashboard {dashboard.get('title', dashboard_path.name)}: {result.get('status', 'ok')} {result.get('url', '')}")
else:
    print(f"Local dashboard directory not found: {local_dashboard_dir}", file=sys.stderr)

print(f"Open traffic dashboard: {grafana_url}/d/actual-ml-traffic-control/smartcat-traffic-control?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s")
PY
