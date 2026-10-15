{{- define "centrifuge-api-v4-activation.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-activation.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-activation.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: activation
{{- end }}

{{- define "centrifuge-api-v4-activation.labels" -}}
{{ include "centrifuge-api-v4-activation.selectorLabels" . }}
app.kubernetes.io/part-of: cfg-api-v4
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
One Job per operation. The operation ID is the only thing that makes the name
unique, so a name that would be truncated is refused rather than shortened.
*/}}
{{- define "centrifuge-api-v4-activation.jobName" -}}
{{- $name := printf "%s-%s" .Release.Name .Values.operation.operationId }}
{{- if gt (len $name) 63 }}
{{- fail (printf "Job name %s is longer than 63 characters; shorten operation.operationId" $name) }}
{{- end }}
{{- $name }}
{{- end }}
