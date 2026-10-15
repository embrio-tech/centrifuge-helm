{{- define "centrifuge-api-v4-query.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-query.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-query.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-query.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: query
api-v4.centrifuge.io/query-id: {{ .Values.id | quote }}
{{- end }}

{{- define "centrifuge-api-v4-query.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-query.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: query
api-v4.centrifuge.io/query-id: {{ .Values.id | quote }}
{{- end }}

{{- define "centrifuge-api-v4-query.validate" -}}
{{- if not (regexMatch "^q-[0-9]{8}-[0-9]{2}$" .Values.id) }}
{{- fail "id must be a Query ID q-YYYYMMDD-NN" }}
{{- end }}
{{- if not (regexMatch "^pj_[0-9]{8}_[0-9]{2}$" .Values.schema) }}
{{- fail "schema must be pj_YYYYMMDD_NN" }}
{{- end }}
{{- if not .Values.databaseSecretName }}
{{- fail "databaseSecretName is required" }}
{{- end }}
{{- if not .Values.image.digest }}
{{- fail "image.digest is required" }}
{{- end }}
{{- if ne .Values.readOnly true }}
{{- fail "readOnly must be true" }}
{{- end }}
{{- end }}
