#!/usr/bin/env bash
# Collect public_ro SQL connection details for every enabled sql-ro Service,
# and test connectivity with psql (falls back to a TCP probe).
#
# The host reported is the public host to connect to, resolved in this order:
#   1. SQL_RO_HOST environment override
#   2. external-dns hostname annotation on the Service (legacy api-v4-public)
#   3. first non-localhost name in the CNPG Cluster certificate alt DNS names
#      (greenfield api-v4-database sets these from the Environment sqlRo host)
#   4. the Service LoadBalancer address
#
# If the public host does not answer, the Service load balancer address is tried
# too, and the host is reported as stale so the DNS record can be fixed.
#
# Usage: ./scripts/print-sql-ro-credentials.sh
# Optional: KUBECONFIG=~/.kube/alpha.yaml NAMESPACE=cfg-api SQL_RO_HOST=sql-v4-test.cfg.embrio.tech
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

# sql-ro Services are LoadBalancer Services that select a CNPG pooler named
# <cluster>-pooler-sql-ro. Two Services match that selector: the app-facing
# <release>-sql-ro, and the pooler Service CloudNativePG creates itself
# (<cluster>-postgres-pooler-sql-ro). Keep only the app-facing one.
mapfile -t SERVICES < <(
  kubectl -n "$NAMESPACE" get svc \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.selector.cnpg\.io/poolerName}{"\n"}{end}' \
  | awk '$2 ~ /-pooler-sql-ro$/ && $1 !~ /-pooler-sql-ro$/ {print $1}'
)

if [[ ${#SERVICES[@]} -eq 0 || -z "${SERVICES[0]:-}" ]]; then
  echo "No sql-ro Services in namespace ${NAMESPACE} (no Service selects a CNPG *-pooler-sql-ro pooler)."
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

# Resolves the public host to connect to. Fallback argument is the LoadBalancer address.
public_host() {
  local svc=$1 cluster=$2 lb=$3
  if [[ -n "${SQL_RO_HOST:-}" ]]; then
    printf '%s' "$SQL_RO_HOST"
    return 0
  fi
  local ann
  ann="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.metadata.annotations.external-dns\.alpha\.kubernetes\.io/hostname}' 2>/dev/null || true)"
  if [[ -n "$ann" ]]; then
    printf '%s' "$ann"
    return 0
  fi
  local alt
  alt="$(kubectl -n "$NAMESPACE" get cluster "$cluster" \
    -o jsonpath='{range .spec.certificates.serverAltDNSNames[*]}{@}{"\n"}{end}' 2>/dev/null \
    | awk -v c="$cluster" 'NF && $1 != "localhost" && $1 != c && $1 !~ /\.svc/ && $1 !~ /-rw$/ && $1 !~ /-ro$/ && $1 !~ /-pooler/ {print; exit}')"
  if [[ -n "$alt" ]]; then
    printf '%s' "$alt"
    return 0
  fi
  printf '%s' "$lb"
}

# Percent-encodes a string for use in a URL userinfo component.
urlencode() {
  local s=$1 out="" i c
  for (( i=0; i<${#s}; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9.~_-]) out+="$c" ;;
      *) out+="$(printf '%%%02X' "'$c")" ;;
    esac
  done
  printf '%s' "$out"
}

# Probes host:port as public_ro. Returns 0 on success, 1 on failure, 2 when no
# psql and no nc are available.
probe() {
  local host=$1 port=$2 dbname=$3 user=$4 pass=$5
  if command -v psql >/dev/null; then
    if PGPASSWORD="$pass" psql \
        "host=${host} port=${port} dbname=${dbname} user=${user} sslmode=require connect_timeout=10" \
        -v ON_ERROR_STOP=1 -tAc 'select 1' >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  if command -v nc >/dev/null; then
    if nc -z -w 10 "$host" "$port" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  return 2
}

found=0
missing_secret=0
conn_failed=0
dns_stale=0

for svc in "${SERVICES[@]}"; do
  pooler="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.spec.selector.cnpg\.io/poolerName}')"
  # pooler name: <cluster>-pooler-sql-ro -> cluster: <cluster>
  cluster="${pooler%-pooler-sql-ro}"

  port="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.spec.ports[0].port}')"
  lb="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')"
  host="$(public_host "$svc" "$cluster" "$lb")"

  # K8s Secret names cannot contain '_'; role name stays public_ro.
  ro_secret="${cluster}-public-ro"
  app_secret="${cluster}-app"

  dbname="$(secret_key "$app_secret" dbname 2>/dev/null || true)"
  dbname="${dbname:-app}"
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

  stale_ip=""
  if [[ -z "$host" ]]; then
    echo "Connectivity: SKIPPED (no hostname or load balancer address yet)"
  else
    rc=0
    probe "$host" "$port" "$dbname" "$user" "$pass" || rc=$?
    if [[ "$rc" -eq 2 ]]; then
      echo "Connectivity: SKIPPED (no psql or nc in PATH)"
    elif [[ "$rc" -eq 0 ]]; then
      echo "Connectivity: OK (select 1)"
    elif [[ -n "$lb" && "$host" != "$lb" ]]; then
      rc2=0
      probe "$lb" "$port" "$dbname" "$user" "$pass" || rc2=$?
      if [[ "$rc2" -eq 0 ]]; then
        echo "Connectivity: OK via ${lb}; ${host} is stale, update the DNS record"
        stale_ip="$lb"
        dns_stale=1
      else
        echo "Connectivity: FAILED (${host} and ${lb} both unreachable)"
        conn_failed=1
      fi
    else
      echo "Connectivity: FAILED (${host}:${port})"
      conn_failed=1
    fi
  fi

  echo
  echo "psql \"host=${host} port=${port} dbname=${dbname} user=${user} password=${pass} sslmode=require\""
  echo "postgresql://${user}:$(urlencode "$pass")@${host}:${port}/${dbname}?sslmode=require"
  if [[ -n "$stale_ip" ]]; then
    echo "postgresql://${user}:$(urlencode "$pass")@${stale_ip}:${port}/${dbname}?sslmode=require"
    echo "  (the line above uses the load balancer address until the ${host} DNS record is fixed)"
  fi
  echo
done

if [[ "$found" -eq 0 ]]; then
  echo "No usable public_ro credentials found in ${NAMESPACE}."
  exit 1
fi

if [[ "$missing_secret" -eq 1 ]]; then
  exit 1
fi

if [[ "$conn_failed" -eq 1 ]]; then
  exit 1
fi

if [[ "$dns_stale" -eq 1 ]]; then
  echo "warning: at least one public host is stale; the Service load balancer address answered instead."
  exit 1
fi
