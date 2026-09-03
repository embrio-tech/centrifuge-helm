#!/usr/bin/env bash
# Fetch Helm subchart archives at release time. Not committed to git.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

add_repo() {
  local name=$1 url=$2
  if ! helm repo list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$name"; then
    helm repo add "$name" "$url"
  fi
}

add_repo bitnami https://charts.bitnami.com/bitnami
add_repo redpanda https://charts.redpanda.com
helm repo update bitnami redpanda

for chart in charts/*/; do
  [ -f "${chart}Chart.yaml" ] || continue
  grep -q '^dependencies:' "${chart}Chart.yaml" 2>/dev/null || continue

  mkdir -p "${chart}charts"
  count="$(yq e '.dependencies | length' "${chart}Chart.yaml")"
  for ((i = 0; i < count; i++)); do
    name="$(yq e ".dependencies[$i].name" "${chart}Chart.yaml")"
    version="$(yq e ".dependencies[$i].version" "${chart}Chart.yaml")"
    repo="$(yq e ".dependencies[$i].repository" "${chart}Chart.yaml")"
    dest="${chart}charts/${name}-${version}.tgz"

    if [ -f "$dest" ]; then
      echo "skip existing ${dest}"
      continue
    fi

    case "$repo" in
      file://*)
        echo "skip file dependency ${name} (${repo})"
        ;;
      *cloudnative-pg*)
        echo "fetch CNPG ${name} ${version} -> ${dest}"
        curl -fsSL -o "$dest" \
          "https://github.com/cloudnative-pg/charts/releases/download/${name}-v${version}/${name}-${version}.tgz"
        ;;
      https://charts.bitnami.com/bitnami)
        echo "pull bitnami/${name} ${version} -> ${chart}charts/"
        helm pull "bitnami/${name}" --version "$version" --destination "${chart}charts"
        ;;
      https://charts.redpanda.com)
        echo "pull redpanda/${name} ${version} -> ${chart}charts/"
        helm pull "redpanda/${name}" --version "$version" --destination "${chart}charts"
        ;;
      *)
        echo "::error::unsupported dependency repository for ${name} in ${chart}: ${repo}" >&2
        exit 1
        ;;
    esac
  done
done
