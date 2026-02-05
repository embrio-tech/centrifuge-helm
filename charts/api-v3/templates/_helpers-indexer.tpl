{{/*
Indexer helpers
*/}}
{{- define "centrifuge-api.indexer.name" -}}
{{- default "indexer" .Values.indexer.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api.indexer.fullname" -}}
{{- if .Values.indexer.fullnameOverride }}
{{- .Values.indexer.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "indexer" .Values.indexer.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-api.indexer.labels" -}}
helm.sh/chart: {{ include "centrifuge-api.chart" . }}
{{ include "centrifuge-api.indexer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "centrifuge-api.indexer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api.indexer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
