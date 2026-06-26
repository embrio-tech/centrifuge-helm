{{/*
CLI helpers
*/}}
{{- define "centrifuge-api.cli.name" -}}
{{- default "cli" .Values.cli.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api.cli.fullname" -}}
{{- if .Values.cli.fullnameOverride }}
{{- .Values.cli.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "cli" .Values.cli.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-api.cli.labels" -}}
helm.sh/chart: {{ include "centrifuge-api.chart" . }}
{{ include "centrifuge-api.cli.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "centrifuge-api.cli.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api.cli.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
