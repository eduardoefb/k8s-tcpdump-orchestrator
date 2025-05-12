# k8s-tcpdump-orchestrator

A Kubernetes-native tool to remotely launch, monitor, stop, and collect `tcpdump` sessions across multiple pods and namespaces using Jobs. Ideal for debugging network behavior in distributed environments.

---

## 📦 Tcpdump Container Image

To build and upload the tcpdump image to your Harbor registry:

```bash
cd images/tcpdump
bash create_image.sh
```

Make sure your script builds the image and pushes it to a registry accessible by your Kubernetes cluster.

---

## 🚀 Usage

### Start monitoring multiple pods

Each of the following commands launches a tcpdump Job on the **same node** where the specified pod is running, but in the chosen Job namespace:

```bash
./monitor.sh --pod-name plmna-nrf-0 --namespace plmna --job-namespace default
./monitor.sh --pod-name plmna-bsf-0 --namespace plmna --job-namespace default
./monitor.sh --pod-name plmnb-scp-0 --namespace plmnb --job-namespace default
```

> ⚠️ Note: The pod name/namespace refer to the target pod to monitor. The job will run in the namespace passed via `--job-namespace`.

---

### Check the current status

```bash
./monitor.sh --status
```

This shows whether `tcpdump` is currently running, has finished, or if the job no longer exists.

---

### Stop all running tcpdump sessions

```bash
./monitor.sh --stop-tcpdump
```

This will remove the control file inside the pod, causing the running `tcpdump` to terminate gracefully.

---

### Collect captured files

```bash
./monitor.sh --get-files
```

Downloads all captured `.pcap` files from each job into a temporary local directory, then merges them using `mergecap` into a single file:
```
merged_all.pcap
```

> Original files are preserved. Requires `mergecap` to be installed (from Wireshark CLI tools).

---

### Reset job tracking

```bash
./monitor.sh --reset
```

Clears the internal job tracking list (`jobs.list`) to start fresh.

---

## ✅ Requirements

- `kubectl` access to the cluster
- `mergecap` (from [Wireshark CLI](https://www.wireshark.org/docs/man-pages/mergecap.html)) for file merging
- Kubernetes >= 1.18

---

## 📁 Structure

```
.
├── monitor.sh              # Main script to orchestrate tcpdump jobs
├── job_template.yaml       # Kubernetes Job YAML template
├── jobs.list               # (Auto-generated) Tracks all jobs
└── images/
    └── tcpdump/
        └── create_image.sh # Builds tcpdump image
```

---

## 🔒 Notes

- The container uses `hostPID: true` to access host-level process IDs for tcpdump filtering.
- Make sure RBAC and PodSecurityPolicy (if used) allow privileged jobs and host access.



