#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://github.com/RADAR-base/RADAR-Kubernetes.git"
REPO_DIR="${HOME}/RADAR-Kubernetes"
REPO_DIR_SET=false
K3S_VERSION="v1.33.2+k3s1"
KUBECTL_VERSION="v1.33.2"
HELM_VERSION="v3.16.3"
HELMFILE_VERSION="v0.169.1"
HELM_DIFF_VERSION="v3.9.12"
YQ_VERSION="v4.44.3"
DNAME="CN=RADAR Base,O=RADAR Base,L=Unknown,C=NL"
SERVER_NAME=""
MAINTAINER_EMAIL=""
KUBE_CONTEXT=""

INSTALL_TOOLS=true
INSTALL_K3S="auto"
APPLY_DEV_CONFIG=false
DEPLOY=false
ASSUME_YES=false
CHECK_CLUSTER_ONLY=false
DEPLOY_RETRIES=4
DEPLOY_RETRY_DELAY=20
KUBE_API_WAIT_SECONDS=120
KUBE_API_CHECK_INTERVAL=5

log() {
  printf "\n[INFO] %s\n" "$1"
}

warn() {
  printf "\n[WARN] %s\n" "$1"
}

die() {
  printf "\n[ERROR] %s\n" "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./setup-radar-kubernetes.sh [options]

Options:
  --repo-url URL             Repository URL (default: RADAR-Kubernetes upstream)
  --repo-dir PATH            Target directory for repository clone/update
  --dname VALUE              X.500 name for keystore generation
  --server-name NAME         Override server_name in etc/production.yaml
  --maintainer-email EMAIL   Override maintainer_email in etc/production.yaml
  --kube-context NAME        Override kubeContext in etc/production.yaml
  --install-k3s              Force install K3s
  --skip-k3s                 Skip K3s installation
  --dev-config               Set dev-friendly values in etc/production.yaml
  --deploy                   Run helmfile sync after init/config
  --check-cluster-health     Check Kubernetes API/k3s health and exit
  --skip-tools               Skip tool installation checks/installs
  -y, --yes                  Non-interactive mode where possible
  -h, --help                 Show this help message

Examples:
  ./setup-radar-kubernetes.sh --dev-config --install-k3s
  ./setup-radar-kubernetes.sh --repo-dir "$HOME/RADAR-Kubernetes" --deploy
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Required command '$1' is missing."
  fi
}

sudo_cmd() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    need_cmd sudo
    sudo "$@"
  fi
}

confirm() {
  local prompt="$1"
  if [ "$ASSUME_YES" = true ]; then
    return 0
  fi
  printf "%s [y/N]: " "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

get_primary_ip() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i == "src") {print $(i+1); exit}}'
  fi
}

refresh_kubeconfig_from_k3s() {
  if [ ! -f /etc/rancher/k3s/k3s.yaml ]; then
    return 1
  fi

  mkdir -p "${HOME}/.kube"
  cp /etc/rancher/k3s/k3s.yaml "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"

  local node_ip
  node_ip="$(get_primary_ip || true)"
  if [ -n "${node_ip}" ]; then
    sed -i "s/127.0.0.1/${node_ip}/" "${HOME}/.kube/config" || true
  fi

  return 0
}

ensure_valid_kubeconfig() {
  if ! command -v kubectl >/dev/null 2>&1; then
    return
  fi

  local server
  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
  if [ -n "$server" ] && [ "$server" != "https://:6443" ]; then
    return
  fi

  warn "Detected invalid kubeconfig server value (${server:-empty}). Attempting automatic repair from K3s config."
  if refresh_kubeconfig_from_k3s; then
    server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
    if [ -n "$server" ] && [ "$server" != "https://:6443" ]; then
      log "Kubeconfig repaired: ${server}"
      return
    fi
  fi

  warn "Automatic kubeconfig repair did not produce a valid server."
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo-url)
        REPO_URL="$2"
        shift 2
        ;;
      --repo-dir)
        REPO_DIR="$2"
        REPO_DIR_SET=true
        shift 2
        ;;
      --dname)
        DNAME="$2"
        shift 2
        ;;
      --server-name)
        SERVER_NAME="$2"
        shift 2
        ;;
      --maintainer-email)
        MAINTAINER_EMAIL="$2"
        shift 2
        ;;
      --kube-context)
        KUBE_CONTEXT="$2"
        shift 2
        ;;
      --install-k3s)
        INSTALL_K3S="yes"
        shift
        ;;
      --skip-k3s)
        INSTALL_K3S="no"
        shift
        ;;
      --dev-config)
        APPLY_DEV_CONFIG=true
        shift
        ;;
      --deploy)
        DEPLOY=true
        shift
        ;;
      --check-cluster-health)
        CHECK_CLUSTER_ONLY=true
        shift
        ;;
      --skip-tools)
        INSTALL_TOOLS=false
        shift
        ;;
      -y|--yes)
        ASSUME_YES=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

install_base_packages() {
  local pkg_manager
  if command -v apt-get >/dev/null 2>&1; then
    pkg_manager="apt"
  elif command -v dnf >/dev/null 2>&1; then
    pkg_manager="dnf"
  elif command -v yum >/dev/null 2>&1; then
    pkg_manager="yum"
  elif command -v pacman >/dev/null 2>&1; then
    pkg_manager="pacman"
  elif command -v zypper >/dev/null 2>&1; then
    pkg_manager="zypper"
  else
    die "No supported package manager found. Install dependencies manually."
  fi

  case "$pkg_manager" in
    apt)
      sudo_cmd apt-get update
      sudo_cmd apt-get install -y curl git openssl ca-certificates tar gzip jq openjdk-17-jre-headless
      ;;
    dnf)
      sudo_cmd dnf install -y curl git openssl ca-certificates tar gzip jq java-17-openjdk
      ;;
    yum)
      sudo_cmd yum install -y curl git openssl ca-certificates tar gzip jq java-17-openjdk
      ;;
    pacman)
      sudo_cmd pacman -Sy --noconfirm --needed curl git openssl ca-certificates tar gzip jq jre17-openjdk
      ;;
    zypper)
      sudo_cmd zypper --non-interactive install curl git openssl ca-certificates tar gzip jq java-17-openjdk
      ;;
  esac
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    log "kubectl already installed: $(kubectl version --client --short 2>/dev/null || true)"
    return
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported architecture for kubectl: $arch" ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl" -o "${tmp_dir}/kubectl"
  chmod +x "${tmp_dir}/kubectl"
  sudo_cmd install -m 0755 "${tmp_dir}/kubectl" /usr/local/bin/kubectl
  rm -rf "${tmp_dir}"
  log "Installed kubectl ${KUBECTL_VERSION}"
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    log "Helm already installed: $(helm version --short 2>/dev/null || true)"
    return
  fi

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${tmp_dir}/get_helm.sh"
  chmod 700 "${tmp_dir}/get_helm.sh"
  HELM_INSTALL_DIR="/usr/local/bin" DESIRED_VERSION="${HELM_VERSION}" sudo_cmd "${tmp_dir}/get_helm.sh"
  rm -rf "${tmp_dir}"
  log "Installed Helm ${HELM_VERSION}"
}

install_helmfile() {
  if command -v helmfile >/dev/null 2>&1; then
    log "Helmfile already installed: $(helmfile --version 2>/dev/null || true)"
    return
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported architecture for helmfile: $arch" ;;
  esac

  local tmp_dir tarball
  tmp_dir="$(mktemp -d)"
  tarball="helmfile_${HELMFILE_VERSION#v}_linux_${arch}.tar.gz"
  curl -fsSL "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/${tarball}" -o "${tmp_dir}/${tarball}"
  tar -xzf "${tmp_dir}/${tarball}" -C "${tmp_dir}"
  sudo_cmd install -m 0755 "${tmp_dir}/helmfile" /usr/local/bin/helmfile
  rm -rf "${tmp_dir}"
  log "Installed Helmfile ${HELMFILE_VERSION}"
}

install_yq() {
  if command -v yq >/dev/null 2>&1; then
    log "yq already installed: $(yq --version 2>/dev/null || true)"
    return
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported architecture for yq: $arch" ;;
  esac

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${arch}" -o "${tmp_dir}/yq"
  chmod +x "${tmp_dir}/yq"
  sudo_cmd install -m 0755 "${tmp_dir}/yq" /usr/local/bin/yq
  rm -rf "${tmp_dir}"
  log "Installed yq ${YQ_VERSION}"
}

install_helm_diff() {
  if helm plugin list 2>/dev/null | grep -q '^diff'; then
    log "Helm diff plugin already installed"
    return
  fi

  helm plugin install https://github.com/databus23/helm-diff --version "${HELM_DIFF_VERSION}"
  log "Installed Helm diff ${HELM_DIFF_VERSION}"
}

install_tools() {
  log "Installing/checking required tools"
  install_base_packages
  install_kubectl
  install_helm
  install_helmfile
  install_yq
  install_helm_diff

  need_cmd keytool
  need_cmd openssl
  need_cmd git
  need_cmd curl
}

has_kube_context() {
  kubectl config current-context >/dev/null 2>&1
}

get_effective_kube_context() {
  if [ -n "$KUBE_CONTEXT" ]; then
    printf "%s" "$KUBE_CONTEXT"
    return
  fi

  if has_kube_context; then
    kubectl config current-context
    return
  fi

  printf ""
}

kubectl_with_optional_context() {
  local kube_context="$1"
  shift

  if [ -n "$kube_context" ]; then
    kubectl --context "$kube_context" "$@"
  else
    kubectl "$@"
  fi
}

kube_api_reachable() {
  local kube_context="$1"
  local timeout_seconds="${2:-8}"

  kubectl_with_optional_context "$kube_context" --request-timeout="${timeout_seconds}s" get --raw=/readyz >/dev/null 2>&1
}

wait_for_kube_api() {
  local kube_context="$1"
  local timeout_seconds="$2"
  local elapsed=0

  while [ "$elapsed" -lt "$timeout_seconds" ]; do
    if kube_api_reachable "$kube_context" 8; then
      return 0
    fi
    sleep "${KUBE_API_CHECK_INTERVAL}"
    elapsed=$((elapsed + KUBE_API_CHECK_INTERVAL))
  done

  return 1
}

print_local_k3s_diagnostics() {
  if ! command -v systemctl >/dev/null 2>&1; then
    return
  fi

  if ! systemctl list-unit-files k3s.service >/dev/null 2>&1; then
    return
  fi

  local k3s_state
  k3s_state="$(systemctl is-active k3s 2>/dev/null || true)"

  if [ "$k3s_state" != "active" ]; then
    warn "Local k3s service state is '${k3s_state:-unknown}'."

    if command -v journalctl >/dev/null 2>&1; then
      local recent_fatal
      recent_fatal="$(journalctl -u k3s -n 200 --no-pager 2>/dev/null | grep -m1 'failed to find interface with specified node ip' || true)"
      if [ -n "$recent_fatal" ]; then
        warn "k3s reports a stale node IP/interface mismatch. Network changed since the last successful k3s boot."
      fi
    fi

    warn "Inspect with: sudo systemctl status k3s --no-pager -n 50"
    warn "Inspect logs with: sudo journalctl -u k3s -n 200 --no-pager"
  fi
}

run_cluster_health_check() {
  local kube_context
  kube_context="$(get_effective_kube_context)"

  if [ -z "$kube_context" ]; then
    warn "No active kubectl context found. Cluster health check cannot continue."
    return 1
  fi

  log "Checking Kubernetes API health for context '${kube_context}'"
  if wait_for_kube_api "$kube_context" "${KUBE_API_WAIT_SECONDS}"; then
    log "Kubernetes API is reachable for context '${kube_context}'"
    return 0
  fi

  print_local_k3s_diagnostics
  warn "Kubernetes API is unreachable for context '${kube_context}' after ${KUBE_API_WAIT_SECONDS}s."
  return 1
}

helm_with_context() {
  local kube_context="$1"
  shift

  if [ -n "$kube_context" ]; then
    helm --kube-context "$kube_context" "$@"
  else
    helm "$@"
  fi
}

clear_pending_helm_releases() {
  local kube_context="$1"
  local pending_releases
  pending_releases="$(helm_with_context "$kube_context" list --pending -q 2>/dev/null || true)"

  if [ -z "$pending_releases" ]; then
    return
  fi

  warn "Detected Helm releases with pending state. Attempting automatic recovery."

  while IFS= read -r release; do
    [ -z "$release" ] && continue

    local status
    status="$(helm_with_context "$kube_context" status "$release" 2>/dev/null | awk '/^STATUS:/{print $2}' | head -n1)"
    warn "Recovering release '${release}' in status '${status:-unknown}'."

    case "$status" in
      pending-install|pending-upgrade|pending-rollback)
        local deployed_revision
        deployed_revision="$(helm_with_context "$kube_context" history "$release" 2>/dev/null | awk '$3=="deployed"{rev=$1} END{print rev}')"
        if [ -n "$deployed_revision" ]; then
          helm_with_context "$kube_context" rollback "$release" "$deployed_revision" --wait --timeout 300s || true
        else
          helm_with_context "$kube_context" uninstall "$release" || true
        fi
        ;;
      *)
        warn "Release '${release}' is pending but status parsing was inconclusive; leaving unchanged."
        ;;
    esac
  done <<< "$pending_releases"
}

install_k3s_if_needed() {
  if [ "$INSTALL_K3S" = "no" ]; then
    log "Skipping K3s install by user request"
    return
  fi

  if [ "$INSTALL_K3S" = "auto" ] && has_kube_context; then
    log "Existing kubectl context found: $(kubectl config current-context)"
    return
  fi

  if [ "$INSTALL_K3S" = "auto" ]; then
    if ! confirm "No kubectl context found. Install K3s ${K3S_VERSION}?"; then
      warn "K3s installation skipped. Configure kubectl context before deploy."
      return
    fi
  fi

  log "Installing K3s ${K3S_VERSION}"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="${K3S_VERSION}" K3S_KUBECONFIG_MODE="644" INSTALL_K3S_SYMLINK="skip" sh -s - --disable traefik --disable-helm-controller

  if [ -f /etc/rancher/k3s/k3s.yaml ]; then
    if ! refresh_kubeconfig_from_k3s; then
      warn "Failed to refresh kubeconfig from K3s."
    fi
  fi

  if has_kube_context; then
    log "Active kubectl context: $(kubectl config current-context)"
  else
    warn "K3s installed, but kubectl context is not active. Configure kubeconfig manually."
  fi
}

setup_repo() {
  if [ -d "${REPO_DIR}/.git" ]; then
    log "Repository exists. Updating ${REPO_DIR}"
    if [ -n "$(git -C "${REPO_DIR}" status --porcelain)" ]; then
      warn "Repository has local changes. Skipping git pull --rebase to avoid conflicts."
    else
      git -C "${REPO_DIR}" pull --rebase
    fi
  else
    log "Cloning RADAR-Kubernetes into ${REPO_DIR}"
    git clone "${REPO_URL}" "${REPO_DIR}"
  fi

  git -C "${REPO_DIR}" submodule update --init --recursive
}

run_init() {
  if [ -f "${REPO_DIR}/etc/secrets.yaml" ] && [ -f "${REPO_DIR}/etc/production.yaml" ] && [ -f "${REPO_DIR}/etc/management-portal/keystore.p12" ]; then
    log "Initialization artifacts already exist. Skipping bin/init to preserve current secrets/config."
    return
  fi

  log "Running repository init scripts"
  (
    cd "${REPO_DIR}"
    DNAME="${DNAME}" bin/init
  )
}

apply_dev_values() {
  if [ "$APPLY_DEV_CONFIG" != true ]; then
    return
  fi

  log "Applying dev-friendly values in etc/production.yaml"
  local production_file
  production_file="${REPO_DIR}/etc/production.yaml"

  local context
  context="${KUBE_CONTEXT}"
  if [ -z "$context" ] && has_kube_context; then
    context="$(kubectl config current-context)"
  fi

  if [ -n "$context" ]; then
    yq -i ".kubeContext = \"${context}\"" "$production_file"
  fi

  if [ -n "$SERVER_NAME" ]; then
    yq -i ".server_name = \"${SERVER_NAME}\"" "$production_file"
  else
    yq -i '.server_name = "localhost"' "$production_file"
  fi

  if [ -n "$MAINTAINER_EMAIL" ]; then
    yq -i ".maintainer_email = \"${MAINTAINER_EMAIL}\"" "$production_file"
  fi

  yq -i '.dev_deployment = true' "$production_file"
  log "Dev configuration applied"
}

deploy_stack() {
  if [ "$DEPLOY" != true ]; then
    warn "Skipping deployment. Configure files and run: (cd ${REPO_DIR} && helmfile sync)"
    return
  fi

  log "Deploying RADAR-Kubernetes with helmfile sync"

  local kube_context
  kube_context="$(get_effective_kube_context)"

  if [ -n "$kube_context" ] && ! wait_for_kube_api "$kube_context" "${KUBE_API_WAIT_SECONDS}"; then
    print_local_k3s_diagnostics
    die "Kubernetes API is not reachable for context '${kube_context}' after ${KUBE_API_WAIT_SECONDS}s. Ensure the cluster is running and try again."
  fi

  local attempt
  for attempt in $(seq 1 "${DEPLOY_RETRIES}"); do
    if [ -n "$kube_context" ] && ! kube_api_reachable "$kube_context" 8; then
      warn "Kubernetes API became unreachable for context '${kube_context}'. Waiting up to ${KUBE_API_WAIT_SECONDS}s before retrying."
      if ! wait_for_kube_api "$kube_context" "${KUBE_API_WAIT_SECONDS}"; then
        print_local_k3s_diagnostics
        die "Kubernetes API is still unreachable for context '${kube_context}'. Aborting deployment retries."
      fi
    fi

    clear_pending_helm_releases "$kube_context"

    if (
      cd "${REPO_DIR}"
      helmfile --concurrency 1 sync
    ); then
      log "Deployment completed"
      return
    fi

    if [ "$attempt" -lt "$DEPLOY_RETRIES" ]; then
      warn "helmfile sync failed (attempt ${attempt}/${DEPLOY_RETRIES}). Retrying in ${DEPLOY_RETRY_DELAY}s..."
      sleep "${DEPLOY_RETRY_DELAY}"
    fi
  done

  die "helmfile sync failed after ${DEPLOY_RETRIES} attempts. Check network/repo reachability and rerun."
}

main() {
  parse_args "$@"

  if [ "$REPO_DIR_SET" = false ] && [ -f "$PWD/bin/init" ] && [ -f "$PWD/etc/base.yaml" ]; then
    REPO_DIR="$PWD"
  fi

  [ "$(uname -s)" = "Linux" ] || die "This script currently supports Linux only."

  if [ "$INSTALL_TOOLS" = true ]; then
    install_tools
  else
    log "Skipping tool installation checks"
  fi

  install_k3s_if_needed
  ensure_valid_kubeconfig

  local health_checked=false
  local health_ok=true
  if [ "$CHECK_CLUSTER_ONLY" = true ] || has_kube_context; then
    health_checked=true
    if ! run_cluster_health_check; then
      health_ok=false
    fi
  fi

  if [ "$CHECK_CLUSTER_ONLY" = true ]; then
    if [ "$health_ok" = true ]; then
      log "Cluster health check passed"
      exit 0
    fi

    die "Cluster health check failed. Fix cluster availability and rerun."
  fi

  if [ "$health_checked" = true ] && [ "$health_ok" != true ] && [ "$DEPLOY" != true ]; then
    warn "Cluster health check failed. Deployment is disabled in this run, but a future --deploy run will fail until the cluster is healthy."
  fi

  setup_repo
  run_init
  apply_dev_values

  log "Initial setup completed"
  printf "\nNext important files to review:\n"
  printf "  - %s/etc/production.yaml\n" "$REPO_DIR"
  printf "  - %s/etc/production.yaml.gotmpl\n" "$REPO_DIR"
  printf "  - %s/etc/secrets.yaml\n" "$REPO_DIR"

  deploy_stack

  printf "\nDone. Repository location: %s\n" "$REPO_DIR"
}

main "$@"
