# proj08 IaC - Smart Transaction Categorization

Infrastructure and Kubernetes manifests for the proj08 integrated ML system. The application repo is `Jiahang-Zhang1/actual` on the `serving` branch. The platform repo deploys the modified Actual Budget UI, SmartCat model serving API, MLflow/MinIO/Postgres, Prometheus/Grafana monitoring, HPA, alerts, and the HTTPS entrypoint required by Chrome.

## Target Architecture

| Layer | Kubernetes namespace | Public port | Purpose |
| --- | --- | ---: | --- |
| Actual Budget HTTPS | `actual-budget` | `30443` | Main UI with SmartCat Top-3 transaction-category predictions. Use this for demos. |
| Actual Budget HTTP fallback | `actual-budget` | `30083` | Debug fallback only. Public HTTP is not a secure context for `SharedArrayBuffer`. |
| SmartCat serving | `smartcat` | `30090` | FastAPI `/predict`, `/predict_batch`, `/metrics`, and monitoring endpoints. |
| MLflow | `gourmetgram-platform` | `8000` | Model registry and run tracking. Namespace kept for compatibility with existing training workflows. |
| Grafana | `monitoring` | `30300` | Infrastructure and application dashboards. Login: `admin` / `admin123`. |
| Prometheus | `monitoring` | `30909` | Metrics backend and alert evaluation. |
| MinIO console | `gourmetgram-platform` | `9001` | Object storage console. Login: `your-access-key` / `PL89sTsyClxjtvQVxjN9`. |
| MinIO API | `gourmetgram-platform` | `9000` | S3-compatible artifact storage. |

## Repo Layout

| Path | Purpose |
| --- | --- |
| `tf/kvm/` | Terraform for the 3-node Chameleon KVM cluster, private network, floating IP, and public service security group. |
| `ansible/` | Ansible/Kubespray inventory and bootstrap playbooks. Update node1 floating IP after Terraform output changes. |
| `k8s/actual-budget/` | Actual Budget Deployment, HTTP fallback Service, and nginx HTTPS NodePort proxy. |
| `k8s/smartcat-serving.yaml` | SmartCat inference Deployment and NodePort Service. |
| `k8s/monitoring/` | HPA, PrometheusRule alerts, ServiceMonitor, and kube-prometheus-stack values. |
| `k8s/platform/` | Helm chart for MLflow, MinIO, and Postgres. |
| `scripts/` | One-command helpers for image loading, platform install, monitoring install, HTTPS setup, service checks, and security groups. |
| `workflows/` | Existing Argo training/build/promote workflow templates. Some templates still contain legacy GourmetGram names and should be updated before relying on Argo for final automation. |
| `initalize_server.ipynb` | Chameleon notebook for reserving the 3 `m1.large` nodes and opening browser demo security groups. |
| `docs/chameleon-one-file-runbook.md` | Single canonical handoff for fresh AI chats, Chameleon rebooking, production-week launch, recording, links, and troubleshooting. |

## Fresh Cluster Deployment

### 1. Reserve Chameleon resources

Run `initalize_server.ipynb` in Chameleon Jupyter, or reserve manually:

- Lease name: `k8s-cluster-zy3180`
- Resource type: Virtual Machine
- Amount: `3`
- Flavor: `m1.large`

The notebook writes the reserved flavor id/name to `/work/proj08-iac/.proj08-reservation.env`. Chameleon exposes this reservation as a reserved OpenStack flavor, so the id is passed to `openstack server create --flavor`.

Before creating resources, run the non-destructive preflight:

```bash
bash scripts/check-chameleon-rebooking-prereqs.sh
```

For a fresh AI chat or tomorrow's recording, use the single consolidated guide:
`docs/chameleon-one-file-runbook.md`.

### 2. Provision the 3-node cluster

The current recommended path is the OpenStack CLI wrapper. This is the route that successfully created the April 2026 cluster after Terraform hit Chameleon KVM service-catalog issues.

```bash
# Run this once to create ~/.config/openstack/clouds.yaml with a KVM@TACC
# application credential. The helper sets auth_url to the KVM Keystone v3
# endpoint and region_name to KVM@TACC.
bash scripts/configure-kvm-clouds-yaml.sh

# Then create the private network, security group, three VMs, floating IP,
# and Ansible/Kubespray inventory files.
KEY_NAME=id_rsa_chameleon bash scripts/create-chameleon-kvm-cluster.sh <reserved-flavor-id>
```

The combined helper wraps these lower-level scripts:

- `scripts/fix-kvm-cloud-region.sh`
- `scripts/openstack-kvm.sh`
- `scripts/provision-kvm-openstack.sh`
- `scripts/render-ansible-inventory.sh`

It writes the result to `artifacts/chameleon/latest-cluster.env` and prints the `floating_ip_out` value for node1. It opens the browser/demo ports used by this project, including `30443`, `30083`, `30090`, `30300`, `30909`, `8000`, `9000`, and `9001`.

Terraform still exists under `tf/kvm/`, but use it only if the provider authentication and KVM service catalog are known to be working in your shell.

### 3. Bootstrap Kubernetes

Use the existing Ansible/Kubespray flow after updating inventory files with node1's floating IP:

```bash
ansible-playbook -i ansible/inventory.yml ansible/pre_k8s/pre_k8s_configure.yml
# Then run the Kubespray playbook from ansible/k8s according to the team's cluster procedure.
ansible-playbook -i ansible/inventory.yml ansible/post_k8s/post_k8s_configure.yml
```

The cluster kubeconfig should exist on node1 at `/etc/kubernetes/admin.conf`.

### 4. Load the Actual Budget image

Copy the latest Actual and SmartCat tarballs to node1, then run from node1:

```bash
export IMAGE_TAR=/path/to/actual-smartcat_actual-sync-serving-<commit>-latest-linux_amd64.tar.gz
export SERVING_IMAGE_TAR=/path/to/actualbudget-serving_latest-linux_amd64.tar.gz
bash scripts/load-actual-image.sh
bash scripts/load-serving-image.sh
```

This tags and pushes to the in-cluster registry:

```text
registry.kube-system.svc.cluster.local:5000/actual-sync:latest
registry.kube-system.svc.cluster.local:5000/actualbudget-serving:latest
```

### 5. Deploy platform, monitoring, serving, and HTTPS

Run on node1:

```bash
export FLOATING_IP=<node1-floating-ip>
export KUBECONFIG=/etc/kubernetes/admin.conf
bash scripts/deploy-k8s-stack.sh
```

The script installs:

- MLflow + MinIO + Postgres from `k8s/platform/`
- kube-prometheus-stack from Helm with Grafana NodePort `30300` and Prometheus NodePort `30909`
- SmartCat serving NodePort `30090`
- SmartCat HPA with CPU threshold `70%` and memory threshold `80%`
- Prometheus alerts for crash loops, high CPU, high memory, and disk pressure
- Actual Budget HTTP fallback NodePort `30083`
- Actual Budget HTTPS nginx NodePort `30443`

### 6. Verify public service access

```bash
bash scripts/check-public-services.sh <node1-floating-ip>
```

Then open:

```text
https://<node1-floating-ip>:30443
https://actual.<node1-floating-ip>.sslip.io:30443
http://<node1-floating-ip>:30090/docs
http://<node1-floating-ip>:30300
http://<node1-floating-ip>:30909
http://<node1-floating-ip>:8000
http://<node1-floating-ip>:9001
```

The HTTPS certificate is self-signed, so Chrome will show a warning. Accept it for the demo. Do not use `http://<node1-floating-ip>:30083` as the main Actual UI because Chrome will block `SharedArrayBuffer` over public HTTP.

### 7. Import Grafana dashboards

After Grafana is reachable, import the classroom/demo dashboards:

```bash
GRAFANA_URL=http://<node1-floating-ip>:30300 \
GRAFANA_USER=admin \
GRAFANA_PASSWORD=admin123 \
PROMETHEUS_UID=prometheus \
bash scripts/import-grafana-dashboards.sh
```

The helper imports Grafana dashboard IDs `1860`, `3119`, and `15760` for Node Exporter, Kubernetes cluster monitoring, and Kubernetes pod views. The provisioning notebook includes the same step as a runnable cell.

## DevOps Requirement Mapping

| Requirement | Implementation |
| --- | --- |
| Infrastructure monitoring | `scripts/install-monitoring.sh` installs kube-prometheus-stack with Node Exporter and kube-state-metrics. Grafana is exposed on `30300`. |
| Automated scaling | `k8s/monitoring/smartcat-hpa.yaml` scales SmartCat from 1 to 5 replicas at CPU `70%` or memory `80%`. |
| Alerting | `k8s/monitoring/alert-rules.yaml` defines `PodCrashLooping`, `HighCPUUsage`, `HighMemoryUsage`, and `DiskSpaceLow`. |
| HTTPS / SharedArrayBuffer | `k8s/actual-budget/nginx-https-proxy.yaml` terminates TLS on `30443` and adds exactly one COOP and COEP header. |
| Unified deployment | `scripts/deploy-k8s-stack.sh` deploys platform services, monitoring, model serving, and Actual UI from one repo. |
| Model registry and artifacts | `k8s/platform/` deploys MLflow, MinIO, and Postgres. |

## Known Follow-ups

The core K8s service deployment is ready, but the Argo workflow files under `workflows/` still include legacy GourmetGram image/model names. Before the final unattended one-week run, update those workflow templates to use the Actual/SmartCat training repo, model name, and service health checks. The manual/cron promotion and rollback logic already exists in the serving branch, but the Argo templates should be aligned before the team presents them as fully automated cluster-native workflows.
