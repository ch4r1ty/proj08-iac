# Chameleon Rebooking And Recovery Runbook

This file captures the exact path that worked for the ECE-GY 9183 Smart Transaction Categorization demo cluster.

## Current Working Cluster

- Floating IP: `129.114.26.122`
- SSH: `ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.26.122`
- node1 private IP: `192.168.1.11`
- node2 private IP: `192.168.1.12`
- node3 private IP: `192.168.1.13`
- kubeconfig on node1: `/etc/kubernetes/admin.conf`
- Chameleon site: `KVM@TACC`
- Last successful lease name: `k8s-cluster-zy3180`
- VM flavor: `m1.large`
- Node count: `3`
- Keypair: `id_rsa_chameleon`

## First Try To Extend The Existing Lease

Use this when the current cluster still exists.

1. Open the Chameleon Horizon dashboard for `KVM@TACC`.
2. Go to `Reservations` or `Leases`.
3. Find lease `k8s-cluster-zy3180`.
4. Choose `Update Lease`.
5. Use the `Prolong for` fields to add time.

Notes:

- Chameleon usually allows lease extension only near the end of the lease window. The public FAQ says renewal is available when about 30 percent or less of the duration remains.
- If the update button is not available, wait until the allowed window or create a new lease.
- If another reservation blocks extension, use the Chameleon help desk or users list.

After extending, verify from the laptop:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.26.122 'hostname; date -u; uptime'
ssh -i ~/.ssh/id_rsa_chameleon cc@129.114.26.122 \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
```

## If The Cluster Expired: Rebook From Chameleon Jupyter

The successful path was not plain Terraform. The reliable flow was:

1. Reserve three `m1.large` VMs with the Chameleon `chi` Python lease API.
2. Use the lease reserved flavor id as the OpenStack `--flavor` value.
3. Create a KVM@TACC application credential in Horizon and save it to `~/.config/openstack/clouds.yaml`.
4. Run `scripts/create-chameleon-kvm-cluster.sh`.
5. Install Kubernetes with Kubespray, then deploy the stack.

Before creating anything, run the non-destructive preflight:

```bash
cd /work/proj08-iac
bash scripts/check-chameleon-rebooking-prereqs.sh
```

If the user starts a brand-new AI chat, paste the handoff in
`docs/chameleon-new-chat-handoff.md` first. That file explains the credential
model, the last working path, and the rehearsal flow with a separate suffix.

In a Chameleon Jupyter notebook, run:

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
```

Clone or refresh the DevOps repo:

```bash
cd /work
if [ -d proj08-iac/.git ]; then
  cd proj08-iac && git fetch origin && git checkout main && git pull --ff-only
else
  git clone https://github.com/ch4r1ty/proj08-iac.git
  cd proj08-iac
fi
```

Create or reuse the lease:

```python
l = lease.Lease(LEASE_NAME, duration=datetime.timedelta(hours=LEASE_HOURS))
l.add_flavor_reservation(id=chi.server.get_flavor_id(FLAVOR_NAME), amount=NODE_COUNT)
l.submit(idempotent=True)
l.show()

reserved_flavor = l.get_reserved_flavors()[0]
RESERVED_FLAVOR_ID = reserved_flavor.id
RESERVED_FLAVOR_NAME = reserved_flavor.name

REPO_DIR.mkdir(parents=True, exist_ok=True)
RESERVATION_ENV.write_text(
    f"PROJECT_SUFFIX={PROJECT_SUFFIX}\n"
    f"LEASE_NAME={LEASE_NAME}\n"
    f"RESERVED_FLAVOR_ID={RESERVED_FLAVOR_ID}\n"
    f"RESERVED_FLAVOR_NAME={RESERVED_FLAVOR_NAME}\n"
    f"KEY_NAME={KEY_NAME}\n"
)
print("Reserved flavor id:", RESERVED_FLAVOR_ID)
```

Create `~/.config/openstack/clouds.yaml` from a KVM@TACC application credential, then run:

```bash
cd /work/proj08-iac
source .proj08-reservation.env
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}" \
SUFFIX="${PROJECT_SUFFIX:-proj08}" \
bash scripts/create-chameleon-kvm-cluster.sh "${RESERVED_FLAVOR_ID}"
```

The April 2026 successful command shape was:

```bash
KEY_NAME=id_rsa_chameleon bash scripts/create-chameleon-kvm-cluster.sh 3bb9f2d9-6dd7-4d87-ba7b-74cfb437af8b
```

## After VMs Exist

From your laptop:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@<FLOATING_IP>
```

On node1:

```bash
cd /home/cc/proj08-iac
export KUBECONFIG=/etc/kubernetes/admin.conf
bash scripts/deploy-k8s-stack.sh <FLOATING_IP>
```

Expected demo URLs:

- Actual HTTPS: `https://<FLOATING_IP>:30443`
- SmartCat API: `http://<FLOATING_IP>:30090/docs`
- Grafana: `http://<FLOATING_IP>:30300`
- Prometheus: `http://<FLOATING_IP>:30909`
- MLflow: `http://<FLOATING_IP>:8000`
- MinIO: `http://<FLOATING_IP>:9001`

Credentials:

- Grafana: `admin / admin123`
- MinIO: `your-access-key / PL89sTsyClxjtvQVxjN9`

## Fast Health Check

```bash
FLOATING_IP=129.114.26.122

curl -k "https://${FLOATING_IP}:30443" -I
curl "http://${FLOATING_IP}:30090/healthz"
curl "http://${FLOATING_IP}:30090/predict" \
  -H 'Content-Type: application/json' \
  -d '{"transaction_description":"lyft 18.2 ride home","amount":-18.2,"notes":"","currency":"USD","country":"US"}'
ssh -i ~/.ssh/id_rsa_chameleon cc@"${FLOATING_IP}" \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get pods -A'
```

## Files To Avoid Committing

- `ansible/inventory.yml`
- `ansible/k8s/inventory/mycluster/hosts.yaml`
- `ansible/ansible.cfg` after it has been rendered with a one-off floating IP
- `.venv-kubespray/`
- `artifacts/`
- Docker image tarballs
