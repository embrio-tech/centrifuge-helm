#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/scripts/github-transition-report.mjs"
SOURCE_LIB="$ROOT/scripts/github-transition-report-lib.mjs"
for chart in api-v4-projection api-v4-query api-v4-routes api-v4-activation; do
  for file in github-transition-report.mjs github-transition-report-lib.mjs; do
    copy="$ROOT/charts/$chart/files/$file"
    if ! cmp -s "$ROOT/scripts/$file" "$copy"; then
      echo "drift: charts/$chart/files/$file differs from scripts/$file" >&2
      exit 1
    fi
  done
done
echo "github-transition-report scripts match across charts"
