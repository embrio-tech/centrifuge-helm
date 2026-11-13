#!/usr/bin/env bash
# Lint and schema-check one chart: helm lint --strict and helm template | kubeconform
# for every ci/*-values.yaml, or once with chart defaults when a chart has none.
# Usage: scripts/lint-chart.sh <chart-dir-name>   (e.g. api-v4-query)
set -euo pipefail

chart="charts/${1:?chart dir name required}"
[ -f "${chart}/Chart.yaml" ] || { echo "no chart at ${chart}" >&2; exit 1; }

# CRD schemas (CNPG Cluster, Pooler) come from the community catalog.
crd_schemas='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
kube_version="${KUBE_VERSION:-1.32.0}"

# The CNPG cluster subchart renders `postgresql:` and `bootstrap.initdb:` as null
# when unset. The API server drops the nulls, but the CRD schema rejects them.
skip_kinds=""
if yq e '.dependencies[].name' "${chart}/Chart.yaml" 2>/dev/null | grep -qx cluster; then
  skip_kinds="Cluster"
fi

shopt -s nullglob
values_files=("${chart}"/ci/*-values.yaml)
if [ ${#values_files[@]} -eq 0 ]; then
  values_files=("")
fi

# The erpc chart can enforce a versioned release-name convention
# (erpc.enforceNaming: true, exercised by ci/newinstance-values.yaml). Use a
# conforming release name so that fixture renders; the default-values fixture
# leaves enforceNaming false and is unaffected.
release_name="lint-${1}"
[ "$1" = "erpc" ] && release_name="cfg-api-erpc-eu-v0-5"

for values in "${values_files[@]}"; do
  args=()
  [ -n "$values" ] && args=(-f "$values")
  echo "::group::${chart} ${values:-defaults}"
  helm lint "$chart" --strict "${args[@]}"
  helm template "$release_name" "$chart" "${args[@]}" --kube-version "$kube_version" \
    | kubeconform -strict -summary \
        -kubernetes-version "$kube_version" \
        -schema-location default \
        -schema-location "$crd_schemas" \
        ${skip_kinds:+-skip "$skip_kinds"}
  echo "::endgroup::"
done

# The routes Application orders this chart by sync wave. The in_progress
# reporter is wave -2, after the ConfigMap and before the activation Job.
if [ "$1" = "api-v4-activation" ]; then
  rendered="$(helm template lint-api-v4-activation "$chart" -f "$chart/ci/report-values.yaml" --kube-version "$kube_version")"
  fail=0
  count() { grep -c -F "$1" <<<"$rendered" || true; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-3"')" = 1 ] || { echo "expected one wave -3 ConfigMap" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-2"')" = 1 ] || { echo "expected one wave -2 in_progress reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-1"')" = 1 ] || { echo "expected one wave -1 activation Job" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "0"')" = 1 ] || { echo "expected one wave 0 success reporter" >&2; fail=1; }
  [ "$(grep -c -E 'argocd.argoproj.io/hook: Sync$' <<<"$rendered" || true)" = 3 ] || { echo "expected three Sync hooks" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: PostSync')" = 0 ] || { echo "activation chart must not use PostSync reporters" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: SyncFail')" = 1 ] || { echo "expected one SyncFail reporter" >&2; fail=1; }
  [ "$(count 'report-failure')" = 1 ] || { echo "expected report-failure" >&2; fail=1; }
  [ "$(count 'value: "in_progress"')" = 1 ] || { echo "expected one in_progress report" >&2; fail=1; }
  grep -q 'https://argocd.cloud.embrio.tech/applications/argo/cfg-api-v4-routes-test-eu' <<<"$rendered" || { echo "log URL must name the routes Application" >&2; fail=1; }
  grep -q '/applications/argo/cfg-api/' <<<"$rendered" && { echo "log URL must not include the cfg-api path segment" >&2; fail=1; }
  grep -q 'cfg-api-v4-activation-test-eu' <<<"$rendered" && { echo "log URL must not name the retired activation Application" >&2; fail=1; }
  grep -q 'name: REPORT_PROJECTION_ID' <<<"$rendered" || { echo "success reporter must set REPORT_PROJECTION_ID" >&2; fail=1; }
  grep -q 'value: "pj-20261014-01"' <<<"$rendered" || { echo "REPORT_PROJECTION_ID must match desiredProjection" >&2; fail=1; }
  [ "$fail" = 0 ] || exit 1
fi

if [ "$1" = "api-v4-projection" ]; then
  rendered="$(helm template lint-api-v4-projection "$chart" -f "$chart/ci/report-values.yaml" --kube-version "$kube_version")"
  fail=0
  count() { grep -c -F "$1" <<<"$rendered" || true; }
  [ "$(count 'argocd.argoproj.io/hook: PreSync')" = 3 ] || { echo "expected Producer health gate, report ConfigMap, and in_progress reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: PostSync')" = 2 ] || { echo "expected Producer-ready report gate and success reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: SyncFail')" = 1 ] || { echo "expected one SyncFail reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-1"')" = 1 ] || { echo "expected one PreSync wave -1 report ConfigMap" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "0"')" = 2 ] || { echo "expected PreSync in_progress reporter and PostSync Producer-ready report gate at wave 0" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "1"')" = 2 ] || { echo "expected PreSync Producer health gate and PostSync success reporter at wave 1" >&2; fail=1; }
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pr-20261021-01-indexer:8080/health"')" = 1 ] || { echo "Producer health gate URL must name the Projection Producer" >&2; fail=1; }
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pr-20261021-01-indexer:8080/ready"')" = 1 ] || { echo "Producer-ready report gate URL must name the Projection Producer" >&2; fail=1; }
  [ "$(count 'name: PRODUCER_DISCOVERY_URL')" = 1 ] || { echo "Projection must set PRODUCER_DISCOVERY_URL" >&2; fail=1; }
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pr-20261021-01-indexer:8080"')" = 1 ] || { echo "PRODUCER_DISCOVERY_URL must be the Producer Service base URL (handlers append /discovery)" >&2; fail=1; }
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pj-20261021-01:3001/ready"')" = 1 ] || { echo "report gate must re-check the Projection /ready" >&2; fail=1; }
  grep -q 'publishNotReadyAddresses: true' <<<"$rendered" || { echo "projection Service must publish not-ready addresses for the Query gate" >&2; fail=1; }
  argo='https://argocd.cloud.embrio.tech/applications/argo/cfg-api-v4-test-eu-pj-20261021-01'
  [ "$(count "value: \"${argo}\"")" = 6 ] || { echo "projection Argo URL must be log and environment URL on all three statuses" >&2; fail=1; }
  grep -q '/applications/argo/cfg-api/' <<<"$rendered" && { echo "log URL must not include the cfg-api path segment" >&2; fail=1; }
  # An env name and its value render on adjacent lines; match the line after the
  # exact name so an equal value under another env var does not count.
  value_after() {
    local name_line="^ *- name: $1\$"
    [ "$(grep -c -E -- "$name_line" <<<"$2" || true)" = 1 ] || return 1
    [ "$(grep -A1 -E -- "$name_line" <<<"$2" | tail -n 1 | sed 's/^ *//')" = "value: \"$3\"" ]
  }
  producer_id_rendered="$(helm template lint-api-v4-projection "$chart" -f "$chart/ci/producer-id-generation-values.yaml" --kube-version "$kube_version")"
  value_after INDEX_GENERATION "$producer_id_rendered" pr-20261013-01 || { echo "Producer-id generation must be INDEX_GENERATION verbatim" >&2; fail=1; }
  value_after REDPANDA_CLIENT_ID "$producer_id_rendered" handlers-test-eu-pr-20261013-01-pj-20261013-01 || { echo "Producer-id generation must be verbatim inside REDPANDA_CLIENT_ID" >&2; fail=1; }
  legacy_rendered="$(helm template lint-api-v4-projection "$chart" -f "$chart/ci/default-values.yaml" --kube-version "$kube_version")"
  value_after INDEX_GENERATION "$legacy_rendered" id202610130000 || { echo "INDEX_GENERATION must come from generation, not producerId" >&2; fail=1; }
  value_after REDPANDA_CLIENT_ID "$legacy_rendered" handlers-test-eu-id202610130000-pj-20261013-01 || { echo "REDPANDA_CLIENT_ID must carry generation, not producerId" >&2; fail=1; }
  [ "$fail" = 0 ] || exit 1
fi

if [ "$1" = "api-v4-query" ]; then
  rendered="$(helm template lint-api-v4-query "$chart" -f "$chart/ci/report-values.yaml" --kube-version "$kube_version")"
  fail=0
  count() { grep -c -F "$1" <<<"$rendered" || true; }
  [ "$(count 'argocd.argoproj.io/hook: PreSync')" = 3 ] || { echo "expected PreSync ConfigMap, in_progress reporter, and Projection health gate" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-1"')" = 1 ] || { echo "expected one PreSync wave -1 report ConfigMap" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "1"')" = 1 ] || { echo "expected one PreSync wave 1 Projection health gate" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: PostSync')" = 1 ] || { echo "expected one PostSync reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: SyncFail')" = 1 ] || { echo "expected one SyncFail reporter" >&2; fail=1; }
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pj-20261021-01:3001/health"')" = 1 ] || { echo "Projection health gate URL must name the Query Projection" >&2; fail=1; }
  [ "$(count 'value: "https://cfg.embrio.tech/test/20261021-01"')" = 3 ] || { echo "preview URL must be environment_url on all three statuses" >&2; fail=1; }
  [ "$(count 'value: "https://argocd.cloud.embrio.tech/applications/argo/cfg-api-v4-test-eu-q-20261021-01"')" = 3 ] || { echo "query Argo URL must be log_url on all three statuses" >&2; fail=1; }
  grep -q '/applications/argo/cfg-api/' <<<"$rendered" && { echo "log URL must not include the cfg-api path segment" >&2; fail=1; }
  grep -q 'path: /test/20261021-01' <<<"$rendered" || { echo "preview Ingress path missing" >&2; fail=1; }
  grep -q 'stripPrefix:' <<<"$rendered" || { echo "preview stripPrefix missing" >&2; fail=1; }
  grep -q -- '- "/test/20261021-01"' <<<"$rendered" || { echo "stripPrefix must remove the preview path" >&2; fail=1; }
  grep -q 'type: ClusterIP' <<<"$rendered" || { echo "query Service must stay ClusterIP" >&2; fail=1; }
  grep -q 'api-v4.centrifuge.io/hook: "true"' <<<"$rendered" || { echo "hook Pods must not carry workload selector labels" >&2; fail=1; }
  producer_id_rendered="$(helm template lint-api-v4-query "$chart" -f "$chart/ci/producer-id-values.yaml" --kube-version "$kube_version")"
  grep -q 'value: "http://cfg-api-v4-test-eu-pr-20261013-01-indexer:8080/metrics"' <<<"$producer_id_rendered" || { echo "producerId must render PRODUCER_METRICS_URL to the Producer /metrics Service" >&2; fail=1; }
  grep -q 'name: PRODUCER_METRICS_TTL_MS' <<<"$producer_id_rendered" || { echo "producerMetricsTtlMs must render PRODUCER_METRICS_TTL_MS" >&2; fail=1; }
  grep -q 'PRODUCER_METRICS_URL' <<<"$rendered" && { echo "PRODUCER_METRICS_URL must be absent without producerId" >&2; fail=1; }
  grep -q 'PRODUCER_METRICS_TTL_MS' <<<"$rendered" && { echo "PRODUCER_METRICS_TTL_MS must be absent without producerId" >&2; fail=1; }
  [ "$fail" = 0 ] || exit 1
fi

if [ "$1" = "api-v4-event-lake" ]; then
  rendered="$(helm template lint-api-v4-event-lake "$chart" -f "$chart/ci/report-values.yaml" --kube-version "$kube_version")"
  fail=0
  count() { grep -c -F "$1" <<<"$rendered" || true; }
  [ "$(count 'argocd.argoproj.io/hook: PreSync')" = 2 ] || { echo "expected PreSync ConfigMap and in_progress reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-1"')" = 1 ] || { echo "expected one PreSync wave -1 report ConfigMap" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: PostSync')" = 1 ] || { echo "expected one PostSync reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: SyncFail')" = 1 ] || { echo "expected one SyncFail reporter" >&2; fail=1; }
  [ "$(count 'value: "test-eu-pr-20261013-01"')" = 3 ] || { echo "producer GitHub environment must be environment-id" >&2; fail=1; }
  [ "$(count 'value: "api-v4:indexing"')" = 3 ] || { echo "producer task must be api-v4:indexing" >&2; fail=1; }
  argo='https://argocd.cloud.embrio.tech/applications/argo/cfg-api-v4-test-eu-pr-20261013-01'
  [ "$(count "value: \"${argo}\"")" = 6 ] || { echo "producer Argo URL must be log and environment URL on all three statuses" >&2; fail=1; }
  grep -q 'publishNotReadyAddresses: true' <<<"$rendered" || { echo "indexer Service must publish not-ready addresses for the Projection gate" >&2; fail=1; }
  grep -q '/applications/argo/cfg-api/' <<<"$rendered" && { echo "log URL must not include the cfg-api path segment" >&2; fail=1; }
  # An env name and its value render on adjacent lines; match the line after the
  # exact name so an equal value under another env var does not count.
  value_after() {
    local name_line="^ *- name: $1\$"
    [ "$(grep -c -E -- "$name_line" <<<"$2" || true)" = 1 ] || return 1
    [ "$(grep -A1 -E -- "$name_line" <<<"$2" | tail -n 1 | sed 's/^ *//')" = "value: \"$3\"" ]
  }
  value_after ENVIO_PG_SCHEMA "$rendered" id202610130000 || { echo "legacy generation must be the Envio schema unchanged" >&2; fail=1; }
  producer_id_rendered="$(helm template lint-api-v4-event-lake "$chart" -f "$chart/ci/producer-id-generation-values.yaml" --kube-version "$kube_version")"
  value_after ENVIO_PG_SCHEMA "$producer_id_rendered" pr_20261013_01 || { echo "Producer-id generation must be the Envio schema with - replaced by _" >&2; fail=1; }
  value_after INDEX_GENERATION "$producer_id_rendered" pr-20261013-01 || { echo "Producer-id generation must be INDEX_GENERATION verbatim" >&2; fail=1; }
  # WebSocket endpoints are opt-in, the same gate as the erpc chart's
  # server.webSocket.enabled: absent by default, mapped per chain only when enabled.
  [ "$(count 'ENVIO_RPC_WS_')" = 0 ] || { echo "WebSocket env must stay absent unless erpc.webSocket.enabled is true" >&2; fail=1; }
  ws_rendered="$(helm template lint-api-v4-event-lake "$chart" -f "$chart/ci/report-values.yaml" --set erpc.webSocket.enabled=true --kube-version "$kube_version")"
  [ "$(grep -c -F 'ENVIO_RPC_WS_' <<<"$ws_rendered" || true)" = 3 ] || { echo "erpc.webSocket.enabled must emit one ws endpoint per selected chain" >&2; fail=1; }
  grep -q -F 'ENVIO_RPC_WS_11155111: ws://cfg-api-erpc:4000/main/evm/11155111' <<<"$ws_rendered" || { echo "erpc.webSocket.enabled must map urlTemplate to its per-chain ws form" >&2; fail=1; }
  [ "$fail" = 0 ] || exit 1
fi

# eRPC side-by-side migration: a versioned new instance must be naming-isolated,
# carry the line label, size Postgres for the cache TTL, and set expiring cache
# TTLs; a non-conforming release name must fail the render (erpc.enforceNaming).
if [ "$1" = "erpc" ]; then
  rendered="$(helm template cfg-api-erpc-eu-v0-5 "$chart" -f "$chart/ci/newinstance-values.yaml" --kube-version "$kube_version")"
  fail=0
  count() { grep -c -F "$1" <<<"$rendered" || true; }
  grep -q 'erpc.cfg/line: "v0-5"' <<<"$rendered" || { echo "new instance must carry the erpc.cfg/line metadata label" >&2; fail=1; }
  grep -q 'name: cfg-api-erpc-eu-v0-5-postgres' <<<"$rendered" || { echo "CNPG cluster must be <release>-postgres" >&2; fail=1; }
  [ "$(count 'ttl: 168h')" -ge 1 ] || { echo "new instance cache policies must set ttl: 168h" >&2; fail=1; }
  grep -q 'size: 128Gi' <<<"$rendered" || { echo "new instance data PVC must be 128Gi" >&2; fail=1; }
  grep -q 'size: 32Gi' <<<"$rendered" || { echo "new instance WAL PVC must be 32Gi" >&2; fail=1; }
  # Naming enforcement: a non-conforming release name must fail the render.
  if helm template cfg-api-erpc "$chart" -f "$chart/ci/newinstance-values.yaml" >/dev/null 2>&1; then
    echo "erpc.enforceNaming must reject a non-conforming release name" >&2; fail=1
  fi
  # TTL enforcement: a zero cache TTL must fail the render for an enforced instance.
  if helm template cfg-api-erpc-eu-v0-5 "$chart" \
       -f "$chart/ci/newinstance-values.yaml" --set erpc.database.evmJsonRpcCache.postgresql.finalizedTtl=0 >/dev/null 2>&1; then
    echo "erpc.enforceNaming must reject a zero cache TTL" >&2; fail=1
  fi
  [ "$fail" = 0 ] || exit 1
fi
