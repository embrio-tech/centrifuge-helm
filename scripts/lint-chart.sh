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

for values in "${values_files[@]}"; do
  args=()
  [ -n "$values" ] && args=(-f "$values")
  echo "::group::${chart} ${values:-defaults}"
  helm lint "$chart" --strict "${args[@]}"
  helm template "lint-${1}" "$chart" "${args[@]}" --kube-version "$kube_version" \
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
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pr-20261021-01-indexer:8080/discovery"')" = 1 ] || { echo "PRODUCER_DISCOVERY_URL must name the Producer discovery endpoint" >&2; fail=1; }
  [ "$(count 'value: "http://cfg-api-v4-test-eu-pj-20261021-01:3001/ready"')" = 1 ] || { echo "report gate must re-check the Projection /ready" >&2; fail=1; }
  grep -q 'publishNotReadyAddresses: true' <<<"$rendered" || { echo "projection Service must publish not-ready addresses for the Query gate" >&2; fail=1; }
  argo='https://argocd.cloud.embrio.tech/applications/argo/cfg-api-v4-test-eu-pj-20261021-01'
  [ "$(count "value: \"${argo}\"")" = 6 ] || { echo "projection Argo URL must be log and environment URL on all three statuses" >&2; fail=1; }
  grep -q '/applications/argo/cfg-api/' <<<"$rendered" && { echo "log URL must not include the cfg-api path segment" >&2; fail=1; }
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
  [ "$fail" = 0 ] || exit 1
fi
