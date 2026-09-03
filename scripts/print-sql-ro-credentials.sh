#!/usr/bin/env bash
# Collect public_ro SQL connection details for every enabled sql-ro Service.
# Usage: ./scripts/print-sql-ro-credentials.sh
# Optional: KUBECONFIG=~/.kube/alpha.yaml NAMESPACE=cfg-api
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/alpha.yaml}"
NAMESPACE="${NAMESPACE:-cfg-api}"

die() { echo "error: $*" >&2; exit 1; }

if [[ ! -f "$KUBECONFIG" ]]; then
  die "kubeconfig not found: $KUBECONFIG"
fi

if ! command -v kubectl >/dev/null; then
  die "kubectl not found in PATH"
fi

mapfile -t SERVICES < <(
  kubectl -n "$NAMESPACE" get svc -l app.kubernetes.io/name=sql-ro \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

if [[ ${#SERVICES[@]} -eq 0 || -z "${SERVICES[0]:-}" ]]; then
  echo "No sql-ro Services in namespace ${NAMESPACE} (label app.kubernetes.io/name=sql-ro)."
  exit 0
fi

b64() {
  if base64 --help 2>&1 | grep -q -- '-d'; then
    base64 -d
  else
    base64 -D
  fi
}

secret_key() {
  local secret=$1 key=$2
  if ! kubectl -n "$NAMESPACE" get secret "$secret" >/dev/null 2>&1; then
    return 1
  fi
  local raw
  raw="$(kubectl -n "$NAMESPACE" get secret "$secret" -o "jsonpath={.data.${key}}" 2>/dev/null || true)"
  [[ -n "$raw" ]] || return 1
  printf '%s' "$raw" | b64
}

found=0
missing_secret=0

for svc in "${SERVICES[@]}"; do
  host="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.metadata.annotations.external-dns\.alpha\.kubernetes\.io/hostname}')"
  port="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.spec.ports[0].port}')"
  lb="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')"
  pooler="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.spec.selector.cnpg\.io/poolerName}')"

  # pooler name: <cluster>-pooler-sql-ro → cluster: <cluster>
  cluster="${pooler%-pooler-sql-ro}"
  # K8s Secret names cannot contain '_'; role name stays public_ro.
  ro_secret="${cluster}-public-ro"
  app_secret="${cluster}-app"

  dbname="$(secret_key "$app_secret" dbname 2>/dev/null || true)"
  dbname="${dbname:-app}"
  host="${host:-$lb}"
  port="${port:-5432}"

  echo "=== ${svc} ==="
  echo "Host:     ${host:-unknown}"
  echo "LB:       ${lb:-pending}"
  echo "Port:     ${port}"
  echo "Database: ${dbname}"
  echo "User:     public_ro"
  echo "SSL:      require"
  echo "Secret:   ${NAMESPACE}/${ro_secret}"

  if ! kubectl -n "$NAMESPACE" get secret "$ro_secret" >/dev/null 2>&1; then
    missing_secret=1
    echo "Password: MISSING"
    echo
    echo "CNPG has not created Secret ${ro_secret}."
    echo "Check: kubectl -n ${NAMESPACE} get cluster ${cluster} -o jsonpath='{.status.managedRolesStatus}'"
    echo "To force a new managed password Secret, temporarily remove public_ro from"
    echo "cluster.spec.managed.roles, sync, then add it back (or ask CNPG to recreate)."
    echo
    continue
  fi

  user="$(secret_key "$ro_secret" username || true)"
  pass="$(secret_key "$ro_secret" password || true)"
  user="${user:-public_ro}"

  if [[ -z "$pass" ]]; then
    missing_secret=1
    echo "Password: MISSING (secret exists but has no password key)"
    echo
    continue
  fi

  found=1
  echo "Password: ${pass}"
  echo
  echo "psql \"host=${host} port=${port} dbname=${dbname} user=${user} password=${pass} sslmode=require\""
  echo
done

if [[ "$found" -eq 0 ]]; then
  echo "No usable public_ro credentials found in ${NAMESPACE}."
  exit 1
fi

if [[ "$missing_secret" -eq 1 ]]; then
  exit 1
fi
