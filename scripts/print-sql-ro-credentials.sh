#!/usr/bin/env bash
# Print public_ro SQL connection strings for every enabled sql-ro Service.
#
# Default output is one line per database: environment, connection string, status.
# Use --verbose (-v) for the full detail (host, load balancer, port, database,
# user, secret name, connectivity detail and the psql command).
#
# The host is the public host to connect to, resolved in this order:
#   1. SQL_RO_HOST environment override
#   2. external-dns hostname annotation on the Service (legacy api-v4-public)
#   3. first non-internal name in the CNPG Cluster certificate alt DNS names
#      (greenfield api-v4-database sets these from the Environment sqlRo host)
#   4. the Service LoadBalancer address
# If the public host does not answer, the load balancer address is tried and the
# host is reported as stale.
#
# Usage: ./scripts/print-sql-ro-credentials.sh [-v|--verbose] [-h|--help]
# Optional: KUBECONFIG=~/.kube/alpha.yaml NAMESPACE=cfg-api SQL_RO_HOST=sql-v4-test.cfg.embrio.tech
set -euo pipefail

VERBOSE=0
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
  esac
done

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

  env_label="$(kubectl -n "$NAMESPACE" get svc "$svc" \
    -o jsonpath='{.metadata.labels.api-v4\.centrifuge\.io/environment}' 2>/dev/null || true)"
  [[ -n "$env_label" ]] || env_label="$svc"

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

  if ! kubectl -n "$NAMESPACE" get secret "$ro_secret" >/dev/null 2>&1; then
    missing_secret=1
    echo "${env_label}: no credentials, Secret ${NAMESPACE}/${ro_secret} is missing" >&2
    if [[ "$VERBOSE" -eq 1 ]]; then
      echo "  CNPG has not created the Secret. Check the Cluster managedRolesStatus, or re-add public_ro"
      echo "  to cluster.spec.managed.roles and sync to have CNPG recreate it."
    fi
    continue
  fi

  user="$(secret_key "$ro_secret" username || true)"
  pass="$(secret_key "$ro_secret" password || true)"
  user="${user:-public_ro}"

  if [[ -z "$pass" ]]; then
    missing_secret=1
    echo "${env_label}: no credentials, Secret ${NAMESPACE}/${ro_secret} has no password key" >&2
    continue
  fi

  found=1
  uri="postgresql://${user}:$(urlencode "$pass")@${host}:${port}/${dbname}?sslmode=require"

  status="ok"
  stale_ip=""
  if [[ -z "$host" ]]; then
    status="skipped"
  else
    rc=0
    probe "$host" "$port" "$dbname" "$user" "$pass" || rc=$?
    if [[ "$rc" -eq 2 ]]; then
      status="skipped"
    elif [[ "$rc" -eq 0 ]]; then
      status="ok"
    elif [[ -n "$lb" && "$host" != "$lb" ]]; then
      rc2=0
      probe "$lb" "$port" "$dbname" "$user" "$pass" || rc2=$?
      if [[ "$rc2" -eq 0 ]]; then
        status="stale"
        stale_ip="$lb"
        dns_stale=1
      else
        status="FAILED"
        conn_failed=1
      fi
    else
      status="FAILED"
      conn_failed=1
    fi
  fi

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "=== ${env_label} (${svc}) ==="
    echo "Host:         ${host:-unknown}"
    echo "LB:           ${lb:-pending}"
    echo "Port:         ${port}"
    echo "Database:     ${dbname}"
    echo "User:         ${user}"
    echo "SSL:          require"
    echo "Secret:       ${NAMESPACE}/${ro_secret}"
    echo "Password:     ${pass}"
    echo "Connectivity: ${status}"
    echo "URI:          ${uri}"
    if [[ -n "$stale_ip" ]]; then
      echo "URI (VIP):    postgresql://${user}:$(urlencode "$pass")@${stale_ip}:${port}/${dbname}?sslmode=require"
    fi
    echo "psql:         psql \"host=${host} port=${port} dbname=${dbname} user=${user} password=${pass} sslmode=require\""
    echo
  else
    printf '%-8s %s  %s\n' "$env_label" "$uri" "$status"
    if [[ -n "$stale_ip" ]]; then
      printf '%-8s postgresql://%s:%s@%s:%s/%s?sslmode=require  %s\n' \
        "$env_label" "$user" "$(urlencode "$pass")" "$stale_ip" "$port" "$dbname" "VIP (DNS stale)"
    fi
  fi
done

if [[ "$found" -eq 0 ]]; then
  echo "No usable public_ro credentials found in ${NAMESPACE}." >&2
  exit 1
fi

if [[ "$missing_secret" -eq 1 ]]; then
  exit 1
fi

if [[ "$conn_failed" -eq 1 ]]; then
  exit 1
fi

if [[ "$dns_stale" -eq 1 ]]; then
  echo "warning: at least one public host is stale; use the VIP connection string or fix the DNS record." >&2
  exit 1
fi
