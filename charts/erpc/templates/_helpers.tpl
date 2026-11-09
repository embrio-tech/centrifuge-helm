{{/*
Expand the name of the chart.
*/}}
{{- define "erpc.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "erpc.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "erpc.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "erpc.labels" -}}
helm.sh/chart: {{ include "erpc.chart" . }}
{{ include "erpc.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.erpc.lineLabel }}
erpc.cfg/line: {{ . | quote }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "erpc.selectorLabels" -}}
app.kubernetes.io/name: {{ include "erpc.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CloudNative-PG Cluster metadata.name (must match postgres subchart cluster.fullname).
Application credentials secret: <this>-app (key uri, username, password, ...).
*/}}
{{- define "erpc.cnpgClusterFullname" -}}
{{- $p := .Values.postgres }}
{{- if $p.fullnameOverride }}
{{- $p.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "postgres" $p.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Render-time cross-field validation. Included from templates/validate.yaml, which
renders nothing else (see AGENTS.md chart convention 12). Every check is gated on
`erpc.enforceNaming` so legacy releases that leave it at the default `false`
render byte-identically.

Checks:
  - release name matches the versioned side-by-side convention
    `cfg-api-erpc-(eu|us)-v<MAJOR>-<MINOR>` (naming never silently depends on
    Argo defaults);
  - when the Postgres EVM cache is enabled, both expiring TTLs are set to a
    non-zero duration, so new instances can never accumulate permanent rows.
*/}}
{{- define "erpc.validate" -}}
{{- if .Values.erpc.enforceNaming }}
{{- if not (regexMatch "^cfg-api-erpc-(eu|us)-v[0-9]+-[0-9]+$" .Release.Name) }}
{{- fail (printf "erpc.enforceNaming: release name %q must match ^cfg-api-erpc-(eu|us)-v[0-9]+-[0-9]+$" .Release.Name) }}
{{- end }}
{{- $db := (.Values.erpc.database | default dict) }}
{{- $cache := ($db.evmJsonRpcCache | default dict) }}
{{- if $cache.enabled }}
{{- $pg := ($cache.postgresql | default dict) }}
{{- $finalizedTtl := ($pg.finalizedTtl | default "") }}
{{- $unknownTtl := ($pg.unknownTtl | default "") }}
{{- if or (eq (toString $finalizedTtl) "") (eq (toString $finalizedTtl) "0") }}
{{- fail "erpc.enforceNaming: erpc.database.evmJsonRpcCache.postgresql.finalizedTtl must be a non-zero duration (e.g. 168h) so finalized cache rows expire" }}
{{- end }}
{{- if or (eq (toString $unknownTtl) "") (eq (toString $unknownTtl) "0") }}
{{- fail "erpc.enforceNaming: erpc.database.evmJsonRpcCache.postgresql.unknownTtl must be a non-zero duration (e.g. 168h) so unknown-finality cache rows expire" }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
