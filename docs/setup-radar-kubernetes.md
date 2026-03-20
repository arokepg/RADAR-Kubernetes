# Using `setup-radar-kubernetes.sh`

The `setup-radar-kubernetes.sh` script is an automated installation and configuration tool for deploying RADAR-Kubernetes. It handles installing essential tools (like `kubectl`, `helm`, `helmfile`), configuring local Kubernetes clusters (like K3s), setting up the repository, and deploying the stack.

---

## 1. Prerequisites

Before using the script, ensure you are running on a **Linux** system. The script automatically attempts to install missing packages using your system's package manager (`apt`, `dnf`, `yum`, `pacman`, or `zypper`).

## 2. Getting Started

### Make the Script Executable
Before you can run the script, you need to grant it execution permissions. Open your terminal and run:

```bash
chmod +x setup-radar-kubernetes.sh
```

### Basic Execution
You can run the script without any arguments to perform a standard initialization (it will ask for confirmation before installing K3s):

```bash
./setup-radar-kubernetes.sh
```

---

## 3. Usage & Examples

The script supports several flags to customize the installation and deployment process.

### **Local Development Setup**
If you are setting up RADAR-base for local development, you generally want to install K3s, apply local dev configurations, and deploy the stack automatically.

```bash
./setup-radar-kubernetes.sh --dev-config --install-k3s --deploy
```
- `--dev-config`: Automatically sets values in `etc/production.yaml` suitable for local development (e.g., setting the `server_name` to `localhost`).
- `--install-k3s`: Skips the interactive prompt and forces the installation of a local K3s cluster.
- `--deploy`: Runs `helmfile sync` at the end to deploy the RADAR-base components.

### **Non-Interactive / Automated Deployments**
If you want to run the script in a CI/CD pipeline or without human intervention, use the `-y` or `--yes` flag to bypass prompts.

```bash
./setup-radar-kubernetes.sh -y --install-k3s --dev-config --deploy
```

### **Skipping Tool Installations**
If you already have `kubectl`, `helm`, `helmfile`, and `yq` installed and don't want the script to check or update them:

```bash
./setup-radar-kubernetes.sh --skip-tools
```

### **Customizing Configuration Values**
You can override specific settings in the `etc/production.yaml` file directly from the command line:

```bash
./setup-radar-kubernetes.sh \
  --server-name "radar.my-organization.com" \
  --maintainer-email "admin@my-organization.com" \
  --dname "CN=RADAR,O=My Org,L=London,C=UK"
```

### **Checking Cluster Health**
If you are experiencing issues with deployments hanging or failing, you can use the script solely to verify the health of your Kubernetes API and the local K3s service:

```bash
./setup-radar-kubernetes.sh --check-cluster-health
```
*Note: For more details on cluster health checks, see the `cluster_health_check.md` documentation.*

### **Targeting a Specific Directory / Repo**
By default, the script will use the current directory if it looks like a RADAR-Kubernetes setup, or it will clone the upstream repository. You can specify custom repository details:

```bash
./setup-radar-kubernetes.sh \
  --repo-url "https://github.com/YourFork/RADAR-Kubernetes.git" \
  --repo-dir "/opt/radar-base"
```

---

## 4. Full List of Options

| Flag | Description |
|---|---|
| `--repo-url URL` | Repository URL to clone (default: RADAR-Kubernetes upstream). |
| `--repo-dir PATH` | Target directory for the repository clone or update. |
| `--dname VALUE` | X.500 name used for keystore generation. |
| `--server-name NAME` | Overrides the `server_name` property in `etc/production.yaml`. |
| `--maintainer-email EMAIL` | Overrides the `maintainer_email` property in `etc/production.yaml`. |
| `--kube-context NAME` | Sets a specific Kubernetes context to use in `etc/production.yaml`. |
| `--install-k3s` | Forces the installation of K3s without asking. |
| `--skip-k3s` | Skips K3s installation entirely. |
| `--dev-config` | Automatically configures `etc/production.yaml` for local development. |
| `--deploy` | Executes `helmfile sync` after initialization and configuration. |
| `--check-cluster-health`| Checks Kubernetes API/k3s health and exits. |
| `--skip-tools` | Skips downloading/installing prerequisite CLI tools. |
| `-y, --yes` | Runs in non-interactive mode (automatically answers yes to prompts). |
| `-h, --help` | Displays the help message. |

---

## 5. What Happens Under the Hood?

When you run `./setup-radar-kubernetes.sh`, it executes in the following order:

1. **Tool Checks & Installation:** Verifies if required packages and CLI binaries (`helm`, `helmfile`, `kubectl`, `yq`) are present, installing them if missing.
2. **K3s Installation:** Checks if a local Kubernetes cluster is needed and installs it. Fixes `kubeconfig` IP mismatch issues if the host network changes.
3. **Cluster Health Check:** Ensures the Kubernetes API is reachable before attempting heavy operations.
4. **Repository Setup:** Clones or updates the `RADAR-Kubernetes` git repository.
5. **Initialization:** Runs `bin/init` to generate certificates, keystores, and base secrets (unless they already exist).
6. **Configuration Processing:** Modifies `etc/production.yaml` if specific flags (like `--dev-config` or `--server-name`) were provided.
7. **Deployment:** If `--deploy` is specified, runs `helmfile sync` to bring up the full RADAR-base stack, automatically recovering pending helm releases if necessary.
