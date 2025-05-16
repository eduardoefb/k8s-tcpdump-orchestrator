
# k8s-tcpdump-orchestrator

A Kubernetes-native tool to remotely launch, monitor, stop, and collect `tcpdump` sessions across multiple pods and namespaces using Jobs. Ideal for debugging network behavior in distributed environments. Includes a CLI mode and a Web UI orchestration interface.

---

## 📦 Tcpdump & Orchestrator Images

To build and upload the tcpdump and orchestrator images to your Harbor registry:

```bash
cwd=${PWD}
cd images/tcpdump
bash create_image.sh
cd ${cwd}
cd images/orchestrator
bash create_image.sh
```

Make sure your scripts push to a registry accessible by your Kubernetes cluster.

---

## 🚀 CLI Usage (`monitor.sh`)

### Start monitoring specific pods

Each command will launch a tcpdump Job in the specified `--job-namespace` targeting the node of the specified pod:

```bash
./monitor.sh --pod-name plmna-nrf-0 --namespace plmna --job-namespace default
./monitor.sh --pod-name plmna-bsf-0 --namespace plmna --job-namespace default
./monitor.sh --pod-name plmnb-scp-0 --namespace plmnb --job-namespace default
```

---

### Monitor status

```bash
./monitor.sh --status
```

Shows which pods are still running tcpdump or have finished.

---

### Stop tcpdump in all tracked pods

```bash
./monitor.sh --stop-tcpdump
```

Stops capture gracefully by deleting control files in pods.

---

### Download and merge all PCAP files

```bash
./monitor.sh --get-files
```

- Downloads all `.pcap` files into a temporary directory
- Merges them using `mergecap` into `merged_all.pcap`
- Retains original files

---

### Reset internal job tracking

```bash
./monitor.sh --reset
```

Clears the internal `jobs.list`.

---

## 🌐 Web UI Deployment

You can also deploy the orchestrator as a Web UI with the included Kubernetes manifest:

```bash
kubectl apply -f orchestrator_deploy.yaml
```

This will:
- Create the namespace: `tcpdump-orchestrator`
- Deploy a single replica pod with a Flask app
- Expose it on port 80 via a `LoadBalancer` service
- Provide RBAC access to manage jobs and monitor pods

Once deployed, access the UI via the external IP of the service.

---

## ⚙️ Helm & Terraform Deployment

To automate the build and deployment process of the orchestrator using **Helm** and **Terraform**, a helper script `script.sh` is provided.

### Prerequisites

- Vault properly configured with Harbor credentials at `secret/data/harbor-credentials`
- `tofu` (Terraform OpenTofu CLI)
- Access to your Kubernetes cluster via `kubectl`
- `helm`, `helm-push` plugin (`cm-push`)
- `podman` and `buildah` for image builds

### Available commands

```bash
./script.sh create
```

This will:
1. Build the `tcpdump` and `orchestrator` container images
2. Push the Helm chart to your Harbor registry
3. Deploy the orchestrator using Terraform (includes Helm chart installation)

To destroy the deployment:

```bash
./script.sh destroy
```

This will:
- Fully remove the orchestrator deployment (Terraform destroy)

---

## ✅ Requirements

- `kubectl` configured to access your cluster
- `mergecap` installed (`sudo apt install wireshark-common`)
- `podman` and `buildah` for image building
- Kubernetes >= 1.18

---

## 📁 Project Structure

```
.
├── monitor.sh                # Main CLI script
├── job_template.yaml         # Job spec used to launch tcpdump
├── jobs.list                 # Internal list of monitored pods/jobs
├── app.py                    # Flask app used by the Web UI to manage tcpdump jobs via monitor.sh
├── orchestrator_deploy.yaml  # Web UI deployment manifest
├── script.sh                 # Script for Helm + Terraform deployment
├── traces/                   # Directory for downloaded pcap files
└── images/
    ├── tcpdump/              # Tcpdump image Dockerfile & create script
    └── orchestrator/         # Web UI Flask app image
```

---

## 🔒 Notes

- The tcpdump jobs run with `hostPID: true` and require `privileged: true`
- The Web UI pod auto-discovers its own namespace for orchestrating jobs
- RBAC permissions are scoped properly for reading pods and creating jobs
