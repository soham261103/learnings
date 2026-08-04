#!/usr/bin/bash
#
# setup-minikube-monitoring.sh
# Creates a Minikube cluster and installs Prometheus + Grafana via Helm
#
# Usage:m
#   chmod +x setup-minikube-monitoring.sh
#   ./setup-minikube-monitoring.sh
#
# Prerequisites:
#   - minikube  (https://minikube.sigs.k8s.io/docs/start/)
#   - kubectl   (bundled with minikube or install separately)
#   - helm      (https://helm.sh/docs/intro/install/)
#

set -euo pipefail

# ── Config (edit if needed) ────────────────────────────────────────────────
CLUSTER_NAME="${CLUSTER_NAME:-minikube}"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-6144}"  # override if needed: MINIKUBE_MEMORY=4096
MINIKUBE_DRIVER="${MINIKUBE_DRIVER:-docker}"   # docker | hyperv | virtualbox

HELM_RELEASE="${HELM_RELEASE:-kube-prometheus-stack}"
HELM_NAMESPACE="${HELM_NAMESPACE:-monitoring}"
HELM_CHART_REF="prometheus-community/kube-prometheus-stack"
HELM_CHART_VERSION="${HELM_CHART_VERSION:-}"  # empty = latest from repo index
HELM_CHART_CACHE="${HELM_CHART_CACHE:-${TMPDIR:-/tmp}/helm-charts}"

GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-admin}"

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date +'%H:%M:%S')] $*"; }
err()  { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
    command -v "$1" &>/dev/null || err "'$1' not found. Install it first."
}

require_docker() {
    if ! docker info &>/dev/null; then
        err "Docker daemon is not running. Start Docker Desktop (Windows) and enable WSL integration, or run: sudo service docker start"
    fi
}

resolve_helm_chart() {
    local chart_name="kube-prometheus-stack"
    local version="${HELM_CHART_VERSION}"

    if [[ -z "${version}" ]]; then
        version=$(helm show chart "${HELM_CHART_REF}" | awk '/^version:/ {print $2; exit}')
        log "Resolved chart version: ${version}"
    fi

    local tgz="${HELM_CHART_CACHE}/${chart_name}-${version}.tgz"
    local url="https://github.com/prometheus-community/helm-charts/releases/download/${chart_name}-${version}/${chart_name}-${version}.tgz"

    mkdir -p "${HELM_CHART_CACHE}"

    if [[ -f "${tgz}" ]]; then
        log "Using cached chart: ${tgz}"
    else
        log "Downloading ${chart_name} v${version} (curl fallback if helm pull times out)..."
        if helm pull "${HELM_CHART_REF}" --version "${version}" --destination "${HELM_CHART_CACHE}" 2>/dev/null \
            && [[ -f "${tgz}" ]]; then
            log "Downloaded via helm pull"
        else
            require_cmd curl
            curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -o "${tgz}" "${url}"
        fi
    fi

    HELM_CHART="${tgz}"
}

unlock_helm_release_if_stuck() {
    local status
    status=$(helm status "${HELM_RELEASE}" -n "${HELM_NAMESPACE}" \
        -o jsonpath='{.info.status}' 2>/dev/null || true)

    case "${status}" in
        pending-install|pending-upgrade|pending-rollback)
            log "Helm release stuck in '${status}' — clearing lock and retrying install..."
            kubectl delete secret -n "${HELM_NAMESPACE}" \
                -l "owner=helm,name=${HELM_RELEASE}" --ignore-not-found
            ;;
    esac
}

# ── 1) Check prerequisites ───────────────────────────────────────────────────
log "Checking prerequisites..."
require_cmd minikube
require_cmd kubectl
require_cmd helm
require_docker

# ── 2) Start Minikube cluster ────────────────────────────────────────────────
if minikube status -p "${CLUSTER_NAME}" &>/dev/null; then
    log "Minikube profile '${CLUSTER_NAME}' already running — skipping start"
else
    log "Starting Minikube (cpus=${MINIKUBE_CPUS}, memory=${MINIKUBE_MEMORY}MB, driver=${MINIKUBE_DRIVER})..."
    minikube start \
        -p "${CLUSTER_NAME}" \
        --cpus="${MINIKUBE_CPUS}" \
        --memory="${MINIKUBE_MEMORY}" \
        --driver="${MINIKUBE_DRIVER}"
fi

# Point kubectl at this cluster
kubectl config use-context "${CLUSTER_NAME}" || true

log "Cluster info:"
kubectl cluster-info
kubectl get nodes

# ── 3) Enable metrics (optional but useful) ──────────────────────────────────
log "Enabling metrics-server addon..."
minikube addons enable metrics-server -p "${CLUSTER_NAME}" 2>/dev/null || true

# ── 4) Add Helm repos ────────────────────────────────────────────────────────
log "Adding Helm repository: prometheus-community..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null \
    || log "Repo already exists — continuing"
helm repo update

# ── 5) Create namespace ─────────────────────────────────────────────────────
log "Creating namespace: ${HELM_NAMESPACE}"
kubectl create namespace "${HELM_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ── 6) Install kube-prometheus-stack via Helm ────────────────────────────────
# This single chart installs:
#   - Prometheus server
#   - Prometheus Operator
#   - Alertmanager
#   - Grafana (pre-configured with Prometheus datasource)
#   - node-exporter, kube-state-metrics
log "Installing ${HELM_CHART_REF} as release '${HELM_RELEASE}'..."

resolve_helm_chart

unlock_helm_release_if_stuck

HELM_ARGS=(
    upgrade --install "${HELM_RELEASE}" "${HELM_CHART}"
    --namespace "${HELM_NAMESPACE}"
    --create-namespace
    --set "grafana.adminPassword=${GRAFANA_ADMIN_PASSWORD}"
    --set prometheus.prometheusSpec.retention=7d
    --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=5Gi
    --wait
    --timeout 10m
)

log "Running helm upgrade --install (pulls container images; may take 5–10 minutes)..."
if ! helm "${HELM_ARGS[@]}"; then
    err "Helm install failed. Check: kubectl get pods -n ${HELM_NAMESPACE} && kubectl get events -n ${HELM_NAMESPACE} --sort-by=.lastTimestamp"
fi

# ── 7) Wait for pods ─────────────────────────────────────────────────────────
log "Waiting for monitoring pods to be ready..."
kubectl rollout status deployment -n "${HELM_NAMESPACE}" --timeout=300s 2>/dev/null || true
kubectl get pods -n "${HELM_NAMESPACE}"

# ── 8) Print access instructions ─────────────────────────────────────────────
log "Setup complete!"
echo
echo "═══════════════════════════════════════════════════════════════"
echo "  GRAFANA"
echo "═══════════════════════════════════════════════════════════════"
echo "  User:     admin"
echo "  Password: ${GRAFANA_ADMIN_PASSWORD}"
echo
echo "  Option A — port-forward (run in separate terminal):"
echo "    kubectl port-forward -n ${HELM_NAMESPACE} svc/${HELM_RELEASE}-grafana 3000:80"
echo "    Open: http://localhost:3000"
echo
echo "  Option B — minikube service:"
echo "    minikube service ${HELM_RELEASE}-grafana -n ${HELM_NAMESPACE} -p ${CLUSTER_NAME}"
echo
echo "═══════════════════════════════════════════════════════════════"
echo "  PROMETHEUS"
echo "═══════════════════════════════════════════════════════════════"
echo "  Option A — port-forward:"
echo "    kubectl port-forward -n ${HELM_NAMESPACE} svc/${HELM_RELEASE}-prometheus 9090:9090"
echo "    Open: http://localhost:9090"
echo
echo "  Option B — minikube service:"
echo "    minikube service ${HELM_RELEASE}-prometheus -n ${HELM_NAMESPACE} -p ${CLUSTER_NAME}"
echo
echo "═══════════════════════════════════════════════════════════════"
echo "  Useful commands"
echo "═══════════════════════════════════════════════════════════════"
echo "  kubectl get pods -n ${HELM_NAMESPACE}"
echo "  helm list -n ${HELM_NAMESPACE}"
echo "  helm uninstall ${HELM_RELEASE} -n ${HELM_NAMESPACE}   # remove stack"
echo "  minikube delete -p ${CLUSTER_NAME}                   # delete cluster"
echo
