{{/*
Handlers helpers
*/}}
{{- define "centrifuge-api-v4-public.handlers.name" -}}
{{- default "handlers" .Values.handlers.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-public.handlers.fullname" -}}
{{- if .Values.handlers.fullnameOverride }}
{{- .Values.handlers.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "handlers" .Values.handlers.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-public.handlers.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-public.chart" . }}
{{ include "centrifuge-api-v4-public.handlers.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
{{- end }}

{{- define "centrifuge-api-v4-public.handlers.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-public.handlers.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
