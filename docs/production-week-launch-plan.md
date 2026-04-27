# Production Week Fresh Launch Plan

This runbook is for the ECE-GY 9183 "ongoing operation of production system"
week. The instructor will delete active instances and leases at the code freeze
deadline, so the production-week cluster must be brought up fresh.

## What Changes After Code Freeze

- The current Chameleon VMs and leases may disappear after midnight.
- Do not depend on files stored only on node1 local disk.
- GitHub repos, local laptop files, and Chameleon persistent storage are the
  source of truth.
- The floating IP may change after the new lease is created.
- Re-run service checks and use the new IP in the submitted links.

## Tonight Before Midnight

1. Verify the application repo has the final code on GitHub:

   ```bash
   cd /Users/junliu/git_repo/actual
   git fetch origin
   git log --oneline -5 --decorate
   git status --short
   ```

   Expected current application commit:

   ```text
   339beb300 Preserve ML taxonomy in Actual suggestions
   ```

2. Verify the DevOps repo is available on GitHub:

   ```bash
   cd /Users/junliu/git_repo/proj08-iac
   git fetch origin
   git log --oneline -5 --decorate
   git status --short
   ```

3. Keep these local image build commands ready on the laptop:

   ```bash
   cd /Users/junliu/git_repo/actual
   mkdir -p artifacts/docker

   APP_SHA="$(git rev-parse --short HEAD)"
   IMAGE=actual-smartcat/actual-sync \
     TAG="serving-${APP_SHA}-latest" \
     TAR_PATH="artifacts/docker/actual-smartcat_actual-sync-serving-${APP_SHA}-latest-linux_amd64.tar.gz" \
     bash serving/tools/build_actual_sync_image.sh tar

   docker buildx build \
     --platform linux/amd64 \
     --file serving/docker/Dockerfile \
     --tag actualbudget-serving:latest \
     --output type=docker,dest=artifacts/docker/actualbudget-serving_latest-linux_amd64.tar.gz \
     .
   ```

4. Save the required demo credentials:

   ```text
   Grafana: admin / admin123
   MinIO: your-access-key / PL89sTsyClxjtvQVxjN9
   MLflow: no login
   Prometheus: no login
   SmartCat docs: no login
   Actual Budget: use demo/local budget flow unless a sync account is initialized
   ```

## Tomorrow Fresh Cluster Bring-Up

### 1. Rebook Chameleon Lease

Use the existing detailed guide:

```text
docs/chameleon-rebooking-runbook.md
```

The target shape is:

- Site: `KVM@TACC`
- Lease name: `k8s-cluster-zy3180` or a new proj08 name
- Nodes: `3`
- Flavor: `m1.large`, unless the instructor assigns a GPU reservation
- Keypair: `id_rsa_chameleon`

If a GPU reservation is assigned by email, use that reservation only for the
training workload. The serving demo can still run on the 3-node CPU cluster
unless the team intentionally moves serving to the GPU lease.

### 2. Clone DevOps Repo In Chameleon Jupyter

```bash
cd /work
if [ -d proj08-iac/.git ]; then
  cd proj08-iac
  git fetch origin
  git checkout main
  git pull --ff-only
else
  git clone https://github.com/ch4r1ty/proj08-iac.git
  cd proj08-iac
fi
```

### 3. Create VMs And Kubernetes

Follow `docs/chameleon-rebooking-runbook.md`. After the new VMs exist, record:

```text
FLOATING_IP=<new floating ip>
NODE1_PRIVATE=<node1 private ip>
NODE2_PRIVATE=<node2 private ip>
NODE3_PRIVATE=<node3 private ip>
```

Verify SSH:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} 'hostname; date -u; uptime'
```

Verify Kubernetes on node1:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
```

### 4. Build And Copy Images

From the laptop:

```bash
cd /Users/junliu/git_repo/actual
APP_SHA="$(git rev-parse --short HEAD)"
FLOATING_IP=<new floating ip>

scp -i ~/.ssh/id_rsa_chameleon \
  "artifacts/docker/actual-smartcat_actual-sync-serving-${APP_SHA}-latest-linux_amd64.tar.gz" \
  "artifacts/docker/actualbudget-serving_latest-linux_amd64.tar.gz" \
  cc@${FLOATING_IP}:/home/cc/
```

On node1:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP}
mkdir -p /home/cc/proj08-images
mv /home/cc/*actual*.tar.gz /home/cc/proj08-images/ 2>/dev/null || true
```

Clone DevOps on node1 if needed:

```bash
cd /home/cc
if [ -d proj08-iac/.git ]; then
  cd proj08-iac && git pull --ff-only
else
  git clone https://github.com/ch4r1ty/proj08-iac.git
  cd proj08-iac
fi
```

Load images into the in-cluster registry:

```bash
export IMAGE_TAR="$(ls -1 /home/cc/proj08-images/actual-smartcat_actual-sync-serving-*-linux_amd64.tar.gz | tail -1)"
export SERVING_IMAGE_TAR="/home/cc/proj08-images/actualbudget-serving_latest-linux_amd64.tar.gz"

bash scripts/load-actual-image.sh
bash scripts/load-serving-image.sh
```

### 5. Deploy The Stack

On node1:

```bash
cd /home/cc/proj08-iac
export FLOATING_IP=<new floating ip>
export KUBECONFIG=/etc/kubernetes/admin.conf
bash scripts/deploy-k8s-stack.sh
```

The stack should expose:

- Actual HTTPS on `30443`
- Actual HTTP health fallback on `30083`
- SmartCat serving on `30090`
- Grafana on `30300`
- Prometheus on `30909`
- MLflow on `8000`
- MinIO console on `9001`

### 6. Import Dashboards And Open Demo Tabs

From the laptop:

```bash
cd /Users/junliu/git_repo/proj08-iac
FLOATING_IP=<new floating ip>

GRAFANA_URL="http://${FLOATING_IP}:30300" \
GRAFANA_USER=admin \
GRAFANA_PASSWORD=admin123 \
PROMETHEUS_UID=prometheus \
bash scripts/import-grafana-dashboards.sh

bash scripts/check-public-services.sh "${FLOATING_IP}" --open
```

### 7. Production Smoke Test

Run one fast check:

```bash
cd /Users/junliu/git_repo/proj08-iac
FLOATING_IP=<new floating ip> \
bash scripts/freeze-window-smoke.sh --iterations 1
```

Run a longer watch loop during production week:

```bash
cd /Users/junliu/git_repo/proj08-iac
FLOATING_IP=<new floating ip> \
SMARTCAT_TRAFFIC_SOURCE=freeze-window-smoke \
bash scripts/freeze-window-smoke.sh --interval 300 --loop
```

This script only calls public endpoints and optional SmartCat feedback. It does
not mutate Kubernetes resources or Actual budget files.

## Recording Checklist For Four-Person Team

Record a single terminal/browser flow:

1. Show GitHub repos:
   - `https://github.com/Jiahang-Zhang1/actual`
   - `https://github.com/ch4r1ty/proj08-iac`
2. Show fresh Chameleon nodes:

   ```bash
   ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
     'hostname; date -u; sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
   ```

3. Show deployed workloads:

   ```bash
   ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
     'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -A'
   ```

4. Open Actual HTTPS and demonstrate:
   - manual transaction entry
   - AI Suggestion
   - All Top-3
   - clicking a suggested category
5. Open SmartCat API docs and run:
   - `/healthz`
   - `/predict`
   - `/predict_batch`
6. Open Grafana:
   - Traffic Control dashboard
   - System Overview dashboard
   - Model Behavior dashboard
   - Data and Rollout dashboard
7. Open Prometheus targets and show `smartcat-serving` up.
8. Open MLflow and MinIO as model/artifact platform evidence.

## Links To Submit

Replace `<FLOATING_IP>` after the new cluster is created.

```text
Actual Budget HTTPS:
https://<FLOATING_IP>:30443

SmartCat serving API docs:
http://<FLOATING_IP>:30090/docs

Grafana Traffic Control:
http://<FLOATING_IP>:30300/d/actual-ml-traffic-control/smartcat-traffic-control?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Grafana System Overview:
http://<FLOATING_IP>:30300/d/actual-ml-system-overview/actual-ml-system-overview?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Grafana Model Behavior:
http://<FLOATING_IP>:30300/d/actual-ml-model-behavior/model-behavior?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Grafana Data and Rollout:
http://<FLOATING_IP>:30300/d/actual-ml-data-rollout/data-quality-and-rollout?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Prometheus:
http://<FLOATING_IP>:30909/targets

MLflow:
http://<FLOATING_IP>:8000

MinIO Console:
http://<FLOATING_IP>:9001
```

## Brief Notes To Submit

```text
Our production system is deployed on a fresh 3-node Chameleon KVM Kubernetes
cluster. The Actual Budget UI is served over HTTPS and includes SmartCat
transaction category predictions with an AI Suggestion column and an All Top-3
column. Users can manually enter transactions or import bank data; the frontend
calls the SmartCat serving API and displays calibrated Top-3 predictions.
Clicking a suggested category updates the transaction and records feedback for
monitoring and retraining.

The SmartCat FastAPI service exposes /healthz, /predict, /predict_batch,
/metrics, /monitor/summary, and /monitor/decision. The active model is loaded
from the serving image with ONNX dynamic quantization. Prometheus scrapes
service and cluster metrics; Grafana dashboards show traffic, latency,
prediction behavior, feedback acceptance, data quality, and rollout state.
MLflow, MinIO, and Postgres are deployed as the model tracking and artifact
platform. HPA and PrometheusRule alerts are installed for serving resilience.

Grafana login: admin / admin123.
MinIO login: your-access-key / PL89sTsyClxjtvQVxjN9.
Actual uses the demo/local budget flow unless a sync-server account is
initialized for the evaluation.
```

## Known Demo Note

Use `https://<FLOATING_IP>:30443` for Actual. Do not use the HTTP fallback
`http://<FLOATING_IP>:30083` as the main UI because public HTTP is not a secure
context for Chrome `SharedArrayBuffer`.

The TLS certificate is self-signed, so Chrome will show a warning on the first
visit. Accept it for the project demo.
