{{- define "centrifuge-api-v4-projection.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Release names are already unique per object (cfg-api-v4-<environment>-<id>), so the
release name is the resource name.
*/}}
{{- define "centrifuge-api-v4-projection.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels are immutable on a Deployment. The Projection ID is part of them
because a Projection object never changes identity.
*/}}
{{- define "centrifuge-api-v4-projection.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-projection.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: projection
api-v4.centrifuge.io/projection-id: {{ .Values.id | quote }}
{{- end }}

{{/*
Pod labels carry no chart version, so a chart bump alone does not restart the Pod.
*/}}
{{- define "centrifuge-api-v4-projection.podLabels" -}}
{{ include "centrifuge-api-v4-projection.selectorLabels" . }}
app.kubernetes.io/part-of: cfg-api-v4
api-v4.centrifuge.io/producer-id: {{ .Values.producerId | quote }}
{{- with .Values.image.displayTag }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-projection.labels" -}}
{{ include "centrifuge-api-v4-projection.podLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Env vars the chart derives from the object identity. global.env must not set them,
or the Pod would get two entries for one name and the last one silently wins.
*/}}
{{- define "centrifuge-api-v4-projection.reservedEnv" -}}
{{- list "POSTGRAPHILE_DATABASE_URL" "REDPANDA_CLIENT_ID" "PUBLIC_SCHEMA" "INDEX_GENERATION" "PROJECTION_ID" "CFG_NETWORK" "HANDLERS_FAIL_CLOSED" "PRODUCER_DISCOVERY_URL" | toJson }}
{{- end }}

{{- define "centrifuge-api-v4-projection.validate" -}}
{{- $reserved := include "centrifuge-api-v4-projection.reservedEnv" . | fromJsonArray }}
{{- range $key, $_ := .Values.global.env }}
{{- if has $key $reserved }}
{{- fail (printf "global.env.%s is derived by the chart; set the matching top-level value instead" $key) }}
{{- end }}
{{- end }}
{{- range .Values.env }}
{{- if has .name $reserved }}
{{- fail (printf "env %s is derived by the chart; set the matching top-level value instead" .name) }}
{{- end }}
{{- end }}
{{- end }}
