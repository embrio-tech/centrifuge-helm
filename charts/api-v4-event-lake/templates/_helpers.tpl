{{- define "centrifuge-api-v4-event-lake.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Object labels shared by every resource of one Producer.
*/}}
{{- define "centrifuge-api-v4-event-lake.identityLabels" -}}
app.kubernetes.io/part-of: cfg-api-v4
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: producer
api-v4.centrifuge.io/producer-id: {{ .Values.id | quote }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.labels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-event-lake.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ include "centrifuge-api-v4-event-lake.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{ include "centrifuge-api-v4-event-lake.identityLabels" . }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.image" -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.configMapName" -}}
{{- printf "%s-config" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Resolved SELECTED_NETWORKS. A new Producer authors it as an env string in
global.env; an older one still carries a top-level list. Both render the same
ConfigMap value. The chain list is derived here, never authored separately.
*/}}
{{- define "centrifuge-api-v4-event-lake.selectedNetworks" -}}
{{- $env := .Values.global.env | default dict -}}
{{- $fromEnv := index $env "SELECTED_NETWORKS" -}}
{{- if $fromEnv -}}
{{- $fromEnv | toString -}}
{{- else -}}
{{- $networks := list -}}
{{- range .Values.selectedNetworks }}
{{- /* Helm decodes YAML numbers as float64; large chain ids would print as 1.1e+07. */}}
{{- $networks = append $networks (. | int64 | toString) }}
{{- end }}
{{- join "," $networks -}}
{{- end -}}
{{- end }}

{{/*
Runtime env rendered into the ConfigMap. Identity keys come from top-level values
so the Producer object stays the only source for them.
*/}}
{{- define "centrifuge-api-v4-event-lake.configData" -}}
{{- $data := dict -}}
{{- range $key, $value := .Values.global.env }}
{{- $_ := set $data $key ($value | toString) }}
{{- end }}
{{- $_ := set $data "CFG_NETWORK" .Values.network }}
{{- $selected := include "centrifuge-api-v4-event-lake.selectedNetworks" . -}}
{{- if not $selected -}}
{{- fail "set SELECTED_NETWORKS in global.env or a non-empty selectedNetworks list" -}}
{{- end }}
{{- $parts := splitList "," $selected }}
{{- if ne (len $parts) (len (uniq $parts)) }}
{{- fail (printf "SELECTED_NETWORKS has duplicate chain ids: %s" $selected) }}
{{- end }}
{{- $_ := set $data "SELECTED_NETWORKS" $selected }}
{{- range $parts }}
{{- $key := printf "ENVIO_RPC_URL_%s" . }}
{{- if not (hasKey $data $key) }}
{{- $_ := set $data $key (printf $.Values.erpc.urlTemplate .) }}
{{- end }}
{{- end }}
{{- toYaml $data }}
{{- end }}

{{/*
Keys the chart derives. Setting them in global.env or indexer.env would give the
Pod two sources for one name. SELECTED_NETWORKS is authored in global.env (the
chart derives the ConfigMap value from it) so it is refused only in indexer.env.
*/}}
{{- define "centrifuge-api-v4-event-lake.validate" -}}
{{- $globalReserved := list "CFG_NETWORK" "INDEX_GENERATION" "REDPANDA_CLIENT_ID" "PRODUCER_ID" "API_V4_ENVIRONMENT" "ENVIO_PG_HOST" "ENVIO_PG_PORT" "ENVIO_PG_USER" "ENVIO_PG_PASSWORD" "ENVIO_PG_DATABASE" "ENVIO_PG_SCHEMA" }}
{{- $indexerReserved := prepend $globalReserved "SELECTED_NETWORKS" }}
{{- range $key, $_ := .Values.global.env }}
{{- if has $key $globalReserved }}
{{- fail (printf "global.env.%s is derived by the chart; set the matching top-level value instead" $key) }}
{{- end }}
{{- end }}
{{- range .Values.indexer.env }}
{{- if has .name $indexerReserved }}
{{- fail (printf "indexer.env %s is derived by the chart; set the matching top-level value instead" .name) }}
{{- end }}
{{- end }}
{{- end }}
