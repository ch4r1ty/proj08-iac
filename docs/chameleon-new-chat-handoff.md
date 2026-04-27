# Chameleon New Chat Handoff

Copy this file into a fresh Codex/chat session when the project needs to
recreate the ECE-GY 9183 Smart Transaction Categorization production system on
Chameleon.

## What Worked Last Time

The successful path was not a plain Terraform run from the laptop. The reliable
path was:

1. Use Chameleon Jupyter and the `chi` Python API to reserve KVM capacity.
2. Read the lease's reserved flavor id.
3. Use a KVM@TACC application credential in `~/.config/openstack/clouds.yaml`.
4. Run this repo's OpenStack wrapper to create the three VMs, private network,
   security group, sharednet ports, and node1 floating IP.
5. Run Kubespray and then deploy the project stack.

This matters because the notebook `OS_ACCESS_TOKEN` variables can be
short-lived or point to the wrong site. The final working flow intentionally
uses a persistent KVM@TACC application credential and a clean `OS_CLOUD=kvm`
environment.

Official Chameleon notes that KVM@TACC now uses flavor reservations before VM
launch, and that standard non-GPU KVM VM leases can be much longer than GPU
leases. It also documents the `clouds.yaml` application credential shape for
OpenStack automation:

- KVM reservation background:
  <https://blog.chameleoncloud.org/posts/bare-metal-or-kvm-which-should-you-choose-and-when/>
- Lease renewal limit/window:
  <https://www.chameleoncloud.org/learn/frequently-asked-questions/>
- Application credential `clouds.yaml` example:
  <https://blog.chameleoncloud.org/posts/using-terraform-with-chameleon/>

## Current Known Cluster

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

## Hard Rules

- Do not delete, destroy, or overwrite the current cluster unless the user
  explicitly asks for teardown.
- Do not commit generated inventory, `.venv-kubespray`, `artifacts/`, Docker
  image tarballs, or secrets.
- Do not paste application credential secrets into chat or GitHub.
- Use a new `SUFFIX` for rehearsal resources, such as
  `proj08-rehearsal-YYYYMMDDHHMM`, so test resources do not collide with
  production resources.
- Chameleon floating IP DNATs to the node sharednet IP. Kubernetes
  `externalIPs` should bind to node1's sharednet IP, not the floating IP.

## First Diagnostic Command

From the repo root, run this preflight. It does not create or delete resources.

```bash
cd /work/proj08-iac  # in Chameleon Jupyter
# or: cd /Users/junliu/git_repo/proj08-iac on the laptop
bash scripts/check-chameleon-rebooking-prereqs.sh
```

Interpretation:

- Missing `chi` means lease creation should be done in Chameleon Jupyter.
- Missing `openstack` means VM provisioning cannot run from that shell.
- Missing `~/.config/openstack/clouds.yaml` means create a KVM@TACC
  application credential in Horizon and run
  `bash scripts/configure-kvm-clouds-yaml.sh`.
- Failed `token issue` means the application credential is wrong, expired, or
  pointed at the wrong site.

## Recordable Fresh Reservation Flow

Use this in the video after the instructor deletes old leases and instances.

### 1. Open Chameleon Jupyter

Open <https://jupyter.chameleoncloud.org>, start a server, and open a terminal
or notebook.

Clone or refresh the DevOps repo:

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

### 2. Reserve KVM Capacity

Run this in a notebook cell:

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

### 3. Create KVM Application Credential

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

### 4. Create The Three VMs

```bash
cd /work/proj08-iac
source .proj08-reservation.env
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}" \
SUFFIX="${PROJECT_SUFFIX:-proj08}" \
bash scripts/create-chameleon-kvm-cluster.sh "${RESERVED_FLAVOR_ID}"
```

Record the printed `FLOATING_IP`. The script writes:

```text
artifacts/chameleon/latest-cluster.env
```

### 5. Verify The New Server

From the laptop:

```bash
FLOATING_IP=<new floating ip>
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} 'hostname; date -u; uptime'
```

After Kubespray:

```bash
ssh -i ~/.ssh/id_rsa_chameleon cc@${FLOATING_IP} \
  'sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide'
```

## Rehearsal Without Touching Production

If you need to prove the reservation/provisioning path before the real demo,
use a separate name and suffix:

```python
PROJECT_SUFFIX = "proj08-rehearsal"
LEASE_NAME = "proj08-rehearsal-YYYYMMDDHHMM"
NODE_COUNT = 3
LEASE_HOURS = 2
FLAVOR_NAME = "m1.large"
```

Then run:

```bash
cd /work/proj08-iac
source .proj08-reservation.env
SUFFIX="${PROJECT_SUFFIX}" \
KEY_NAME="${KEY_NAME:-id_rsa_chameleon}" \
bash scripts/create-chameleon-kvm-cluster.sh "${RESERVED_FLAVOR_ID}"
```

This creates a separate set of OpenStack resources because the resource names
include the suffix. Clean up rehearsal resources from Horizon/OpenStack when
the recording test is finished, not from the production `proj08` suffix.

## After VM Provisioning

Follow `docs/production-week-launch-plan.md` for image build/copy, Kubespray,
stack deployment, dashboard import, and smoke tests.

Submit links should use the new floating IP:

```text
Actual Budget HTTPS: https://<FLOATING_IP>:30443
SmartCat API docs: http://<FLOATING_IP>:30090/docs
Grafana Traffic Control: http://<FLOATING_IP>:30300/d/actual-ml-traffic-control/smartcat-traffic-control?orgId=1&from=now-1h&to=now&timezone=browser&refresh=5s
Prometheus targets: http://<FLOATING_IP>:30909/targets
MLflow: http://<FLOATING_IP>:8000
MinIO Console: http://<FLOATING_IP>:9001
```

## Likely Failure Meanings

```text
Missing chi
```

Run the reservation cell inside Chameleon Jupyter. The laptop usually does not
have the Chameleon notebook libraries.

```text
Missing ~/.config/openstack/clouds.yaml
```

Create a KVM@TACC application credential in Horizon and run
`scripts/configure-kvm-clouds-yaml.sh`.

```text
Permission denied (publickey)
```

Use the private key matching the Chameleon OpenStack keypair:
`~/.ssh/id_rsa_chameleon`. If testing from Jupyter, make sure the private key
exists in `/work/.ssh` or use the laptop for SSH.

```text
No valid host was found
```

The lease may not be active yet, the reserved flavor id may be wrong, or the
site may lack available KVM capacity. Check `l.show()` in the notebook and the
KVM@TACC lease page.

```text
OpenStack token issue failed
```

The application credential is expired, copied incorrectly, or created for the
wrong site. Recreate a KVM@TACC credential.
