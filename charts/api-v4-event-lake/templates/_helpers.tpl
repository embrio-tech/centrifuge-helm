{{- define "centrifuge-api-v4-event-lake.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-event-lake.chart" . }}
{{ include "centrifuge-api-v4-event-lake.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
{{- if .Values.environment }}
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
{{- end }}
api-v4.centrifuge.io/component: producer
{{- if .Values.id }}
api-v4.centrifuge.io/producer-id: {{ .Values.id | quote }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-event-lake.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.dbSecretName" -}}
{{- if not .Values.databaseSecretName }}
{{- fail "databaseSecretName is required; Producer charts never own CNPG" }}
{{- end }}
{{- .Values.databaseSecretName }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.apiSecretName" -}}
{{- .Values.global.apiSecretName | default "cfg-api-v4-event-lake-rpc-overrides" -}}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.erpcRpcEnv" -}}
{{- $tpl := .Values.erpc.urlTemplate | default "" -}}
{{- if $tpl -}}
{{- $networks := .Values.global.env.SELECTED_NETWORKS | default "" | toString -}}
{{- range splitList "," $networks }}
{{- $id := . | trim -}}
{{- if $id -}}
{{- $key := printf "ENVIO_RPC_URL_%s" $id -}}
{{- if not (hasKey $.Values.global.env $key) }}
{{ $key }}: {{ printf $tpl $id | quote }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.indexGeneration" -}}
{{- $generation := .Values.generation | default (index .Values.global.env "INDEX_GENERATION" | default "") | toString -}}
{{- if not (regexMatch "^id[0-9]{12}$" $generation) -}}
{{- fail "generation / INDEX_GENERATION must match id plus 12 digits" -}}
{{- end -}}
{{- $generation -}}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.clientId" -}}
{{- if .Values.id -}}
{{- printf "envio-origination-%s-%s" .Values.environment .Values.id -}}
{{- else -}}
{{- fail "id (Producer object ID) is required for REDPANDA_CLIENT_ID" -}}
{{- end -}}
{{- end }}
