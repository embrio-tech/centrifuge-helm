{{/*
Handlers helpers
*/}}
{{- define "centrifuge-public-api.handlers.name" -}}
{{- default "handlers" .Values.handlers.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-public-api.handlers.fullname" -}}
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

{{- define "centrifuge-public-api.handlers.labels" -}}
helm.sh/chart: {{ include "centrifuge-public-api.chart" . }}
{{ include "centrifuge-public-api.handlers.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "centrifuge-public-api.handlers.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-public-api.handlers.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
