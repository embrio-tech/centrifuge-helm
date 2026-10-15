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
