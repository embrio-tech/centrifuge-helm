{{/*
Query helpers
*/}}
{{- define "centrifuge-public-api.query.name" -}}
{{- default "query" .Values.query.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-public-api.query.fullname" -}}
{{- if .Values.query.fullnameOverride }}
{{- .Values.query.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "query" .Values.query.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-public-api.query.labels" -}}
helm.sh/chart: {{ include "centrifuge-public-api.chart" . }}
{{ include "centrifuge-public-api.query.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "centrifuge-public-api.query.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-public-api.query.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
