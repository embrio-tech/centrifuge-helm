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

# The routes Application orders this chart by sync wave. A missing wave, a
# SyncFail reporter, or a log URL that still names the old Application ships
# the wrong order.
if [ "$1" = "api-v4-activation" ]; then
  rendered="$(helm template lint-api-v4-activation "$chart" -f "$chart/ci/report-values.yaml" --kube-version "$kube_version")"
  fail=0
  count() { grep -c -F "$1" <<<"$rendered" || true; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-2"')" = 1 ] || { echo "expected one wave -2 ConfigMap" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "-1"')" = 1 ] || { echo "expected one wave -1 activation Job" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/sync-wave: "0"')" = 1 ] || { echo "expected one wave 0 success reporter" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: Sync')" = 2 ] || { echo "expected activation Job and success reporter Sync hooks" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: PostSync')" = 0 ] || { echo "activation chart must not use PostSync reporters" >&2; fail=1; }
  [ "$(count 'argocd.argoproj.io/hook: SyncFail')" = 0 ] || { echo "activation chart must not render a SyncFail reporter" >&2; fail=1; }
  [ "$(count 'report-failure')" = 0 ] || { echo "activation chart must not render report-failure" >&2; fail=1; }
  grep -q 'cfg-api-v4-routes-test-eu' <<<"$rendered" || { echo "log URL must name the routes Application" >&2; fail=1; }
  grep -q 'cfg-api-v4-activation-test-eu' <<<"$rendered" && { echo "log URL must not name the retired activation Application" >&2; fail=1; }
  grep -q 'name: REPORT_PROJECTION_ID' <<<"$rendered" || { echo "success reporter must set REPORT_PROJECTION_ID" >&2; fail=1; }
  grep -q 'value: "pj-20261014-01"' <<<"$rendered" || { echo "REPORT_PROJECTION_ID must match desiredProjection" >&2; fail=1; }
  [ "$fail" = 0 ] || exit 1
fi
