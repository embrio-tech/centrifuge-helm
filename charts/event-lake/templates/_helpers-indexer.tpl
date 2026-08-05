{{/*
Indexer helpers
*/}}
{{- define "centrifuge-event-lake.indexer.name" -}}
{{- default "indexer" .Values.indexer.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-event-lake.indexer.fullname" -}}
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

{{- define "centrifuge-event-lake.indexer.labels" -}}
helm.sh/chart: {{ include "centrifuge-event-lake.chart" . }}
{{ include "centrifuge-event-lake.indexer.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "centrifuge-event-lake.indexer.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-event-lake.indexer.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
