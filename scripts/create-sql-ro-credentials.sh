#!/usr/bin/env bash
# Create public_ro password Secrets for every sql-ro Service and apply them in Postgres.
# CNPG 1.25 does not generate these; passwordSecret must point at an existing basic-auth Secret.
#
# Usage:
#   ./scripts/create-sql-ro-credentials.sh           # create missing only
#   ./scripts/create-sql-ro-credentials.sh --rotate  # regenerate passwords
#
# Optional: KUBECONFIG=~/.kube/alpha.yaml NAMESPACE=cfg-api
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/alpha.yaml}"
NAMESPACE="${NAMESPACE:-cfg-api}"
ROTATE=false
ROLE=public_ro
# K8s Secret names cannot contain '_'; Postgres role name can.
SECRET_SUFFIX=public-ro

for arg in "$@"; do
  case "$arg" in
    --rotate) ROTATE=true ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown arg: $arg" >&2
      exit 1
      ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

[[ -f "$KUBECONFIG" ]] || die "kubeconfig not found: $KUBECONFIG"
command -v kubectl >/dev/null || die "kubectl not found in PATH"
command -v openssl >/dev/null || die "openssl not found in PATH"
command -v jq >/dev/null || die "jq not found in PATH"

mapfile -t SERVICES < <(
  kubectl -n "$NAMESPACE" get svc -l app.kubernetes.io/name=sql-ro \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
)

if [[ ${#SERVICES[@]} -eq 0 || -z "${SERVICES[0]:-}" ]]; then
  echo "No sql-ro Services in namespace ${NAMESPACE}."
  exit 0
fi

ensure_password_secret_ref() {
  local cluster=$1 secret=$2
  local tmp
  tmp="$(mktemp)"
  kubectl -n "$NAMESPACE" get cluster "$cluster" -o json >"$tmp"
  if jq -e --arg role "$ROLE" '
      .spec.managed.roles // []
      | map(select(.name == $role))
      | length > 0
    ' "$tmp" >/dev/null; then
    jq --arg role "$ROLE" --arg secret "$secret" '
      .spec.managed.roles |= map(
        if .name == $role then
          .passwordSecret = {name: $secret}
        else
          .
        end
      )
      | del(.status, .metadata.managedFields, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.generation)
    ' "$tmp" | kubectl -n "$NAMESPACE" apply -f -
  else
    echo "warning: role ${ROLE} not in ${cluster} spec.managed.roles; skip passwordSecret patch" >&2
  fi
  rm -f "$tmp"
}

set_role_password() {
  local cluster=$1 password=$2
  local pod
  pod="$(kubectl -n "$NAMESPACE" get pod \
    -l "cnpg.io/cluster=${cluster},cnpg.io/instanceRole=primary" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  if [[ -z "$pod" ]]; then
    pod="$(kubectl -n "$NAMESPACE" get pod \
      -l "cnpg.io/cluster=${cluster},role=primary" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi
  [[ -n "$pod" ]] || die "no primary pod for cluster ${cluster}"

  # Escape single quotes for SQL string literal.
  local sql_pw
  sql_pw="${password//\'/\'\'}"
  kubectl -n "$NAMESPACE" exec "$pod" -- \
    psql -U postgres -v ON_ERROR_STOP=1 \
    -c "ALTER ROLE ${ROLE} WITH LOGIN PASSWORD '${sql_pw}';"
}

for svc in "${SERVICES[@]}"; do
  pooler="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.spec.selector.cnpg\.io/poolerName}')"
  cluster="${pooler%-pooler-sql-ro}"
  secret="${cluster}-${SECRET_SUFFIX}"

  echo "=== ${svc} ==="
  echo "cluster: ${cluster}"
  echo "secret:  ${NAMESPACE}/${secret}"

  if kubectl -n "$NAMESPACE" get secret "$secret" >/dev/null 2>&1 && [[ "$ROTATE" != true ]]; then
    echo "secret exists (pass --rotate to regenerate)"
  else
    password="$(openssl rand -base64 32 | tr -d '=/+' | head -c 32)"
    kubectl -n "$NAMESPACE" create secret generic "$secret" \
      --type=kubernetes.io/basic-auth \
      --from-literal=username="$ROLE" \
      --from-literal=password="$password" \
      --dry-run=client -o yaml \
      | kubectl -n "$NAMESPACE" apply -f -
    kubectl -n "$NAMESPACE" label secret "$secret" cnpg.io/reload=true --overwrite >/dev/null
    echo "secret written"
    set_role_password "$cluster" "$password"
    echo "ALTER ROLE ${ROLE} applied on primary"
  fi

  ensure_password_secret_ref "$cluster" "$secret"
  echo "passwordSecret -> ${secret}"
  echo
done

echo "Done. Print connection info with:"
echo "  ./scripts/print-sql-ro-credentials.sh"
