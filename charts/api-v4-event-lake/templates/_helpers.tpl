{{/*
Expand the name of the chart.
*/}}
{{- define "centrifuge-api-v4-event-lake.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "centrifuge-api-v4-event-lake.fullname" -}}
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
{{- define "centrifuge-api-v4-event-lake.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "centrifuge-api-v4-event-lake.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-event-lake.chart" . }}
{{ include "centrifuge-api-v4-event-lake.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
{{- end }}

{{/*
Selector labels
*/}}
{{- define "centrifuge-api-v4-event-lake.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-event-lake.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CloudNative-PG Cluster metadata.name (must match postgres subchart cluster.fullname).
Application credentials secret: <this>-app (keys uri, host, port, username, password, dbname).
*/}}
{{- define "centrifuge-api-v4-event-lake.cnpgClusterFullname" -}}
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

{{- define "centrifuge-api-v4-event-lake.dbSecretName" -}}
{{- .Values.global.dbSecretName | default (printf "%s-app" (include "centrifuge-api-v4-event-lake.cnpgClusterFullname" .)) }}
{{- end }}

{{/*
Pre-deployed RPC/HyperSync Secret. Empty values.yaml used to skip the mount
entirely, so a Secret in the namespace never reached the process. Always
resolve a name; the Deployment marks the ref optional so a missing Secret
does not block the pod.
*/}}
{{- define "centrifuge-api-v4-event-lake.apiSecretName" -}}
{{- .Values.global.apiSecretName | default "cfg-api-v4-event-lake-rpc-overrides" -}}
{{- end }}

{{/*
ENVIO_RPC_URL_<chainId> for every id in SELECTED_NETWORKS, pointing at in-cluster
eRPC. Skips keys already set in global.env. No-op when erpc.urlTemplate is empty.
*/}}
{{- define "centrifuge-api-v4-event-lake.erpcRpcEnv" -}}
{{- $tpl := .Values.erpc.urlTemplate | default "" -}}
{{- if $tpl -}}
{{- range splitList "," (.Values.global.env.SELECTED_NETWORKS | default "") }}
{{- $id := . | trim -}}
{{- if $id -}}
{{- $key := printf "ENVIO_RPC_URL_%s" $id -}}
{{- if not (hasKey $.Values.global.env $key) }}
{{ $key }}: {{ printf $tpl $id | quote }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}
