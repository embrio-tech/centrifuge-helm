{{/*
Internet SQL reader (session pooler LoadBalancer) helpers
*/}}
{{- define "centrifuge-api-v4-public.sqlRo.name" -}}
{{- default "sql-ro" .Values.sqlRo.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-public.sqlRo.fullname" -}}
{{- if .Values.sqlRo.fullnameOverride }}
{{- .Values.sqlRo.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "sql-ro" .Values.sqlRo.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-public.sqlRo.poolerName" -}}
{{- printf "%s-pooler-sql-ro" (include "centrifuge-api-v4-public.cnpgClusterFullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-public.sqlRo.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-public.chart" . }}
{{ include "centrifuge-api-v4-public.sqlRo.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
{{- end }}

{{- define "centrifuge-api-v4-public.sqlRo.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-public.sqlRo.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
