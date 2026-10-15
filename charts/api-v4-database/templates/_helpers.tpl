{{- define "centrifuge-api-v4-database.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-database.fullname" -}}
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

{{- define "centrifuge-api-v4-database.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-database.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-database.chart" . }}
{{ include "centrifuge-api-v4-database.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: {{ printf "database-%s" .Values.kind | quote }}
{{- end }}

{{- define "centrifuge-api-v4-database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-database.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "centrifuge-api-v4-database.cnpgClusterFullname" -}}
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

{{- define "centrifuge-api-v4-database.validate" -}}
{{- if not (or (eq .Values.kind "public") (eq .Values.kind "event-lake")) }}
{{- fail "kind must be public or event-lake" }}
{{- end }}
{{- if not .Values.environment }}
{{- fail "environment is required" }}
{{- end }}
{{- if not .Values.postgres.cluster.storage.storageClass }}
{{- fail "postgres.cluster.storage.storageClass is required" }}
{{- end }}
{{- if not .Values.postgres.cluster.storage.size }}
{{- fail "postgres.cluster.storage.size is required" }}
{{- end }}
{{- if ne (default false .Values.postgres.cluster.walStorage.enabled) true }}
{{- fail "postgres.cluster.walStorage.enabled must be true; dedicated WAL is mandatory" }}
{{- end }}
{{- if not .Values.postgres.cluster.walStorage.storageClass }}
{{- fail "postgres.cluster.walStorage.storageClass is required" }}
{{- end }}
{{- if not .Values.postgres.cluster.walStorage.size }}
{{- fail "postgres.cluster.walStorage.size is required" }}
{{- end }}
{{- if and (eq .Values.kind "public") .Values.sqlRo.enabled (not .Values.sqlRo.hostname) }}
{{- fail "sqlRo.hostname is required when sqlRo.enabled is true" }}
{{- end }}
{{- end }}
