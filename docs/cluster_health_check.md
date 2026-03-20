# Cluster health check command

The setup script now supports a dedicated health check mode.

## Command

Run from the repository root:

```bash
./setup-radar-kubernetes.sh --check-cluster-health
```

What it does:

- Detects the effective kubectl context (or uses `--kube-context` if provided).
- Waits up to 120 seconds for Kubernetes API readiness.
- If API is unreachable and local k3s exists, it prints k3s diagnostics hints.
- Exits with code `0` on success, non-zero on failure.

## Optional context override

```bash
./setup-radar-kubernetes.sh --kube-context default --check-cluster-health
```

## Behavior during normal setup runs

For regular setup runs (without `--check-cluster-health`), the script now runs an early cluster health precheck when a kubectl context exists.

- If cluster health is OK, setup continues.
- If cluster health fails and `--deploy` is not set, setup continues with a warning.
- If `--deploy` is set, deployment will stop when the API is unreachable.

## Common failure indicators

If you see messages like these, the cluster control plane is not healthy:

- `Kubernetes cluster unreachable`
- `connect: connection refused`
- `the server is currently unable to handle the request`

For local k3s troubleshooting:

```bash
sudo systemctl status k3s --no-pager -n 50
sudo journalctl -u k3s -n 200 --no-pager
```

## Typical dev workflow

```bash
./setup-radar-kubernetes.sh --check-cluster-health
./setup-radar-kubernetes.sh --dev-config --deploy
```

If the first command fails, fix cluster health first, then retry deploy.
