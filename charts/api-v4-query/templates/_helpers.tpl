{{- define "centrifuge-api-v4-query.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Release names are already unique per object (cfg-api-v4-<environment>-<id>), so the
release name is the resource name.
*/}}
{{- define "centrifuge-api-v4-query.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
The routes chart selects Query Pods by environment, component and query-id only.
Keep those three here and never add a tier or role label.
*/}}
{{- define "centrifuge-api-v4-query.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-query.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: query
api-v4.centrifuge.io/query-id: {{ .Values.id | quote }}
{{- end }}

{{/*
Pod labels carry no chart version, so a chart bump alone does not restart the Pods.
*/}}
{{- define "centrifuge-api-v4-query.podLabels" -}}
{{ include "centrifuge-api-v4-query.selectorLabels" . }}
app.kubernetes.io/part-of: cfg-api-v4
api-v4.centrifuge.io/projection-id: {{ .Values.projectionId | quote }}
{{- with .Values.image.displayTag }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-query.labels" -}}
{{ include "centrifuge-api-v4-query.podLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Env vars the chart derives from the object identity. QUERY_READ_ONLY=false is the
public-api local-dev switch that runs migrations, so a release must never set it.
*/}}
{{/*
Preview host, TLS secret, and URL path segment (main|test). ApplicationSet should
pass preview explicitly; directPreviewByEnvironment is the fallback.
*/}}
{{- define "centrifuge-api-v4-query.previewHost" -}}
{{- if and .Values.preview .Values.preview.host -}}
{{- .Values.preview.host -}}
{{- else if .Values.environment -}}
{{- with index .Values.directPreviewByEnvironment .Values.environment -}}
{{- .host -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "centrifuge-api-v4-query.previewTlsSecret" -}}
{{- if and .Values.preview .Values.preview.tlsSecretName -}}
{{- .Values.preview.tlsSecretName -}}
{{- else if .Values.environment -}}
{{- with index .Values.directPreviewByEnvironment .Values.environment -}}
{{- .tlsSecretName -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "centrifuge-api-v4-query.previewNetwork" -}}
{{- if and .Values.preview .Values.preview.network -}}
{{- .Values.preview.network -}}
{{- else if .Values.environment -}}
{{- index (splitList "-" .Values.environment) 0 -}}
{{- end -}}
{{- end -}}

{{- define "centrifuge-api-v4-query.validate" -}}
{{- $reserved := list "POSTGRAPHILE_DATABASE_URL" "PUBLIC_SCHEMA" "CFG_NETWORK" "QUERY_ID" "PROJECTION_ID" "QUERY_READ_ONLY" }}
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
