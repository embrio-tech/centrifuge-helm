{{/*
Query helpers
*/}}
{{- define "centrifuge-api-v4-public.query.name" -}}
{{- default "query" .Values.query.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-public.query.fullname" -}}
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

{{- define "centrifuge-api-v4-public.query.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-public.chart" . }}
{{ include "centrifuge-api-v4-public.query.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
{{- end }}

{{- define "centrifuge-api-v4-public.query.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-public.query.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
