# Chameleon One-File Runbook

This is the single handoff file for recreating, recording, and operating the
ECE-GY 9183 Smart Transaction Categorization production system on Chameleon.
Paste this whole file into a fresh AI chat if the current chat context is lost.

## 0. Fresh Chat Prompt

```text
We are maintaining and redeploying the ECE-GY 9183 Smart Transaction
Categorization project.

Application repo:
https://github.com/Jiahang-Zhang1/actual.git
Main deployment branch/code target: master/origin master, local repo often uses
branch serving. Do not add [AI] to commit messages.

DevOps/IaC repo:
https://github.com/ch4r1ty/proj08-iac.git
Branch: main.

Goal:
Bring up a fresh 3-node Chameleon KVM Kubernetes cluster after the instructor
deletes old instances/leases, deploy Actual Budget + SmartCat serving +
MLflow/MinIO/Postgres + Prometheus/Grafana, then submit the public service
links. Preserve a recordable terminal/browser flow for the 4-person team video.

Important:
The successful Chameleon path was not a plain Terraform run from the laptop.
Use Chameleon Jupyter + python-chi to create a KVM@TACC flavor lease, then use
a KVM@TACC application credential in ~/.config/openstack/clouds.yaml, then run
proj08-iac/scripts/create-chameleon-kvm-cluster.sh with the reserved flavor id.

Never commit generated inventories, .venv-kubespray, artifacts, Docker tarballs,
or secrets. Do not destroy the current cluster unless explicitly requested.
```

## 1. Current Known Cluster

```text
Floating IP: 129.114.26.122
SSH: ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.26.122
node1 private IP: 192.168.1.11
node2 private IP: 192.168.1.12
node3 private IP: 192.168.1.13
kubeconfig on node1: /etc/kubernetes/admin.conf
site: KVM@TACC
last successful lease name: k8s-cluster-zy3180
VM flavor: m1.large
node count: 3
keypair: id_rsa_chameleon
```

Current public services:

```text
Actual Budget HTTPS: https://129.114.26.122:30443
Actual HTTP health fallback: http://129.114.26.122:30083/health
SmartCat API/docs: http://129.114.26.122:30090/docs
Grafana: http://129.114.26.122:30300/login
Prometheus: http://129.114.26.122:30909
MLflow: http://129.114.26.122:8000
MinIO Console: http://129.114.26.122:9001
```

Credentials:

```text
Grafana: admin / admin123
MinIO: your-access-key / PL89sTsyClxjtvQVxjN9
MLflow: no login
Prometheus: no login
SmartCat API docs: no login
Actual Budget: use demo/local budget flow unless a sync account is initialized
```

## 2. Why The Previous Reservation Worked

The working path was:

1. Chameleon Jupyter used the `chi` Python API to reserve KVM capacity.
2. The lease exposed a reserved flavor id.
3. VM creation used the reserved flavor id as the OpenStack flavor.
4. OpenStack automation used a KVM@TACC application credential stored in
   `~/.config/openstack/clouds.yaml`.
5. The repo script created three VMs, a private network, public security group,
   sharednet ports, and a floating IP on node1.

This avoided two common failure modes:

- short-lived notebook `OS_ACCESS_TOKEN` variables expired or pointed at the
  wrong Chameleon site;
- Terraform/OpenStack provider discovery had trouble with the mixed KVM
  service catalog, so the final successful path used the OpenStack CLI wrapper.

Official references:

- KVM flavor reservation background:
  <https://blog.chameleoncloud.org/posts/bare-metal-or-kvm-which-should-you-choose-and-when/>
- Lease renewal window and limits:
  <https://www.chameleoncloud.org/learn/frequently-asked-questions/>
- Application credential `clouds.yaml` shape:
  <https://blog.chameleoncloud.org/posts/using-terraform-with-chameleon/>

## 3. Hard Rules

- Do not delete, destroy, or overwrite the current cluster unless the user
  explicitly asks for teardown.
- Do not paste application credential secrets into chat or GitHub.
- Do not commit generated files:
  - `ansible/ansible.cfg` after it has been rendered with a one-off IP
  - `ansible/inventory.yml`
  - `ansible/k8s/inventory/mycluster/hosts.yaml`
  - `.venv-kubespray/`
  - `artifacts/`
  - Docker image tarballs
- Use HTTPS `https://<FLOATING_IP>:30443` for Actual UI. Public HTTP is not a
  secure context for Chrome `SharedArrayBuffer`.
- The Actual HTTPS cert is self-signed. Accept the browser warning for the demo.
- Chameleon floating IP DNATs to node1 sharednet IP. Kubernetes `externalIPs`
  should bind to node1 sharednet IP, not the floating IP.
- For rehearsal, use a separate suffix such as `proj08-rehearsal-YYYYMMDDHHMM`.

## 4. Non-Destructive Preflight

Run this before creating anything. It does not reserve leases, create VMs, or
delete resources.

```bash
cd /work/proj08-iac
bash scripts/check-chameleon-rebooking-prereqs.sh
```

On the laptop:

```bash
cd /Users/junliu/git_repo/proj08-iac
bash scripts/check-chameleon-rebooking-prereqs.sh
```

Interpretation:

```text
Missing chi
```

Lease creation should run in Chameleon Jupyter, where python-chi is normally
available.

```text
Missing openstack
```

VM provisioning cannot run from that shell.

```text
Missing ~/.config/openstack/clouds.yaml
```

Create a KVM@TACC application credential in Horizon and run
`bash scripts/configure-kvm-clouds-yaml.sh`.

```text
OpenStack token issue failed
```

The application credential is expired, copied incorrectly, or created for the
wrong site.

## 5. Extend Existing Lease If Possible

Use this only if the current cluster still exists and Chameleon allows
extension.

1. Open KVM@TACC Horizon.
2. Go to `Reservations` or `Leases`.
3. Find lease `k8s-cluster-zy3180`.
4. Choose `Update Lease`.
5. Use `Prolong for` to add time.

Chameleon usually allows lease renewal only when about 30 percent or less of
the lease duration remains. If the button is unavailable, create a fresh lease.

Verify from the laptop:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.26.122 'hostname; date -u; uptime'
ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.26.122 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
```

## 6. Fresh Reservation In Chameleon Jupyter

Use this after the instructor deletes old leases/instances, or when creating a
separate rehearsal cluster.

Open <https://jupyter.chameleoncloud.org>, start a server, and open a terminal
or notebook.

Clone or refresh DevOps repo:

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

Run this in a notebook cell for the real production cluster:

```python
from chi import context, lease
import chi
import datetime
from pathlib import Path

PROJECT_SUFFIX = "proj08"
LEASE_NAME = "k8s-cluster-zy3180"
NODE_COUNT = 3
LEASE_HOURS = 168
FLAVOR_NAME = "m1.large"
KEY_NAME = "id_rsa_chameleon"
REPO_DIR = Path("/work/proj08-iac")
RESERVATION_ENV = REPO_DIR / ".proj08-reservation.env"

context.version = "1.0"
context.choose_project()
context.choose_site(default="KVM@TACC")

l = lease.Lease(LEASE_NAME, duration=datetime.timedelta(hours=LEASE_HOURS))
l.add_flavor_reservation(id=chi.server.get_flavor_id(FLAVOR_NAME), amount=NODE_COUNT)
l.submit(idempotent=True)
l.show()

reserved_flavor = l.get_reserved_flavors()[0]
RESERVED_FLAVOR_ID = reserved_flavor.id
RESERVED_FLAVOR_NAME = reserved_flavor.name

RESERVATION_ENV.write_text(
    f"PROJECT_SUFFIX={PROJECT_SUFFIX}\n"
    f"LEASE_NAME={LEASE_NAME}\n"
    f"RESERVED_FLAVOR_ID={RESERVED_FLAVOR_ID}\n"
    f"RESERVED_FLAVOR_NAME={RESERVED_FLAVOR_NAME}\n"
    f"KEY_NAME={KEY_NAME}\n"
)
print("Reserved flavor id:", RESERVED_FLAVOR_ID)
print("Reserved flavor name:", RESERVED_FLAVOR_NAME)
```

For rehearsal, change only these values:

```python
PROJECT_SUFFIX = "proj08-rehearsal"
LEASE_NAME = "proj08-rehearsal-YYYYMMDDHHMM"
LEASE_HOURS = 2
```

## 7. Configure KVM Application Credential

In KVM@TACC Horizon:

1. Go to `Identity -> Application Credentials`.
2. Create an application credential that expires after the demo window.
3. Copy the generated id and secret.
4. In the Jupyter terminal, run:

```bash
cd /work/proj08-iac
bash scripts/configure-kvm-clouds-yaml.sh
chmod 600 ~/.config/openstack/clouds.yaml
bash scripts/check-chameleon-rebooking-prereqs.sh
```

Do not commit or paste the credential secret.

## 8. Create The Three VMs

Run in Chameleon Jupyter terminal:

```bash
cd /work/proj08-iac
source .proj08-reservation.env
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}" \
SUFFIX="${PROJECT_SUFFIX:-proj08}" \
bash scripts/create-chameleon-kvm-cluster.sh "${RESERVED_FLAVOR_ID}"
```

The script creates:

- private network `192.168.1.0/24`
- node1 `192.168.1.11`
- node2 `192.168.1.12`
- node3 `192.168.1.13`
- public/demo security group
- sharednet ports
- node1 floating IP
- rendered inventory files
- `artifacts/chameleon/latest-cluster.env`

Record the printed floating IP.

Verify from the laptop:

```bash
FLOATING_IP=<new floating ip>
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} 'hostname; date -u; uptime'
```

If SSH gives `Permission denied (publickey)`, make sure the OpenStack keypair is
`id_rsa_chameleon` and the local private key is `~/.ssh/id_rsa_chameleon`.

## 9. Bootstrap Kubernetes

Run the existing Kubespray flow from the DevOps repo. On the host where Ansible
is installed:

```bash
cd /work/proj08-iac
ansible-playbook -i ansible/inventory.yml ansible/pre_k8s/pre_k8s_configure.yml
```

Then run the Kubespray cluster playbook from `ansible/k8s/kubespray` using the
rendered `ansible/k8s/inventory/mycluster/hosts.yaml`.

After Kubespray, verify:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
```

Expected:

```text
node1 Ready control-plane
node2 Ready control-plane
node3 Ready worker
```

## 10. Build Images From Latest Code

From the laptop:

```bash
cd /Users/junliu/git_repo/actual
git fetch origin
git log --oneline -5 --decorate
git status --short

APP_SHA="$(git rev-parse --short HEAD)"
mkdir -p artifacts/docker

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

As of this runbook, the expected app commit is:

```text
ffc335886 Normalize ML feedback category aliases
```

## 11. Copy And Load Images

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

cd /home/cc
if [ -d proj08-iac/.git ]; then
  cd proj08-iac && git pull --ff-only
else
  git clone https://github.com/ch4r1ty/proj08-iac.git
  cd proj08-iac
fi

export IMAGE_TAR="$(ls -1 /home/cc/proj08-images/actual-smartcat_actual-sync-serving-*-linux_amd64.tar.gz | tail -1)"
export SERVING_IMAGE_TAR="/home/cc/proj08-images/actualbudget-serving_latest-linux_amd64.tar.gz"

bash scripts/load-actual-image.sh
bash scripts/load-serving-image.sh
```

Images pushed to the in-cluster registry:

```text
registry.kube-system.svc.cluster.local:5000/actual-sync:latest
registry.kube-system.svc.cluster.local:5000/actualbudget-serving:latest
```

## 12. Deploy The Stack

On node1:

```bash
cd /home/cc/proj08-iac
export FLOATING_IP=<new floating ip>
export KUBECONFIG=/etc/kubernetes/admin.conf
bash scripts/deploy-k8s-stack.sh
```

The stack exposes:

```text
Actual HTTPS: https://<FLOATING_IP>:30443
Actual health fallback: http://<FLOATING_IP>:30083/health
SmartCat API/docs: http://<FLOATING_IP>:30090/docs
Grafana: http://<FLOATING_IP>:30300
Prometheus: http://<FLOATING_IP>:30909
MLflow: http://<FLOATING_IP>:8000
MinIO Console: http://<FLOATING_IP>:9001
```

## 13. Import Dashboards And Open Tabs

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

Useful dashboard links:

```text
Grafana Traffic Control:
http://<FLOATING_IP>:30300/d/actual-ml-traffic-control/smartcat-traffic-control?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Grafana System Overview:
http://<FLOATING_IP>:30300/d/actual-ml-system-overview/actual-ml-system-overview?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Grafana Model Behavior:
http://<FLOATING_IP>:30300/d/actual-ml-model-behavior/model-behavior?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s

Grafana Data and Rollout:
http://<FLOATING_IP>:30300/d/actual-ml-data-rollout/data-quality-and-rollout?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s
```

## 14. Smoke Tests

Public service check:

```bash
cd /Users/junliu/git_repo/proj08-iac
bash scripts/check-public-services.sh <FLOATING_IP>
```

SmartCat direct API:

```bash
FLOATING_IP=<new floating ip>

curl "http://${FLOATING_IP}:30090/healthz"

curl "http://${FLOATING_IP}:30090/predict" \
  -H 'Content-Type: application/json' \
  -d '{"transaction_description":"lyft 18.2 ride home","amount":-18.2,"notes":"","currency":"USD","country":"US"}'

curl "http://${FLOATING_IP}:30090/predict_batch" \
  -H 'Content-Type: application/json' \
  -d '{"transactions":[{"transaction_description":"starbucks no notes","amount":-7.5,"currency":"USD"},{"transaction_description":"payroll direct deposit","amount":2489.41,"currency":"USD"}]}'
```

Freeze-window smoke:

```bash
cd /Users/junliu/git_repo/proj08-iac
FLOATING_IP=<new floating ip> \
bash scripts/freeze-window-smoke.sh --iterations 1
```

Long watch loop during production week:

```bash
cd /Users/junliu/git_repo/proj08-iac
FLOATING_IP=<new floating ip> \
SMARTCAT_TRAFFIC_SOURCE=freeze-window-smoke \
bash scripts/freeze-window-smoke.sh --interval 300 --loop
```

This calls public endpoints and optional SmartCat feedback. It should not mutate
Kubernetes resources or Actual budget files.

## 15. Manual UI Demo Tests

Open:

```text
https://<FLOATING_IP>:30443
```

Test behavior:

- Import records or manually add transactions.
- AI prediction should appear immediately.
- `AI Suggestion` column should show top1 category with green highlight.
- `All Top-3` should show top1 green and the remaining predictions.
- If user clicks another Top-3 category, category should update and that
  selection should be highlighted yellow/orange.
- Feedback should be stored by SmartCat and visible in metrics.

Recommended manual transactions:

```text
Payee: LYFT RIDE TEST
Notes: ride home
Payment: 18.20
Expected: Transport/Transportation, not Income

Payee: STARBUCKS NO NOTES
Notes: empty
Payment: 7.50
Expected: Food

Payee: Payroll Direct Deposit
Notes: deposit
Deposit: 2489.41
Expected: Income

Payee: Netflix.com
Notes: subscription
Payment: 19.09
Expected: Entertainment

Payee: Con Edison Electric
Notes: service
Payment: 154.39
Expected: Utilities

Payee: Quest Diagnostics
Notes: pharmacy or medical
Payment: 99.89
Expected: Healthcare
```

Sparse-input cases to test through API or UI where possible:

```text
empty notes
empty payee with amount
payee only
amount only
currency only
account + amount only
empty payload
malformed payee
merchant and notes disagree
positive amount without income signal
negative amount with income-like word but merchant suggests expense
```

Income should only dominate when there is a positive amount and income-like
text such as payroll, salary, paycheck, employer, direct deposit, or interest.

## 16. Recording Checklist

Record one clear terminal/browser flow:

1. Show GitHub repos:
   - <https://github.com/Jiahang-Zhang1/actual>
   - <https://github.com/ch4r1ty/proj08-iac>
2. Show Chameleon Jupyter reservation cell or Horizon lease page.
3. Show VM creation output with floating IP.
4. Show SSH and nodes:

   ```bash
   ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
     'hostname; date -u; sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
   ```

5. Show pods:

   ```bash
   ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
     'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -A'
   ```

6. Open Actual HTTPS and demonstrate manual transaction prediction.
7. Open SmartCat docs and run `/healthz`, `/predict`, `/predict_batch`.
8. Open Grafana Traffic Control, System Overview, Model Behavior, Data/Rollout.
9. Open Prometheus targets and show SmartCat target up.
10. Open MLflow and MinIO as model/artifact platform evidence.

## 17. Links To Submit

Replace `<FLOATING_IP>`.

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

## 18. Brief Notes To Submit

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

## 19. Common Failure Meanings

```text
No valid host was found
```

The lease may not be active yet, the reserved flavor id may be wrong, or KVM
capacity may be unavailable. Check `l.show()` and the KVM@TACC lease page.

```text
Permission denied (publickey)
```

Use `ssh -i ~/.ssh/id_rsa_chameleon cc@<FLOATING_IP>` and verify the OpenStack
keypair was `id_rsa_chameleon`.

```text
openstack token issue failed
```

Recreate the KVM@TACC application credential and rewrite
`~/.config/openstack/clouds.yaml`.

```text
Chrome blocks Actual over HTTP
```

Use `https://<FLOATING_IP>:30443`, not the HTTP fallback `30083`.

```text
Kubernetes externalIPs do not work
```

Bind services to node1 sharednet IP, not the floating IP, because the floating
IP DNATs to sharednet.

```text
Grafana dashboard has no SmartCat data
```

Generate traffic with `/predict`, `/predict_batch`, manual Actual UI entries,
or `freeze-window-smoke.sh`; then refresh dashboards.
