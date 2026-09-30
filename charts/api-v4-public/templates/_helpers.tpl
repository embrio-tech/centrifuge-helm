{{/*
Expand the name of the chart.
*/}}
{{- define "centrifuge-api-v4-public.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "centrifuge-api-v4-public.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "centrifuge-api-v4-public.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "centrifuge-api-v4-public.labels" -}}
helm.sh/chart: {{ include "centrifuge-api-v4-public.chart" . }}
{{ include "centrifuge-api-v4-public.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
{{- end }}

{{/*
Selector labels
*/}}
{{- define "centrifuge-api-v4-public.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-public.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
CloudNative-PG Cluster metadata.name (must match postgres subchart cluster.fullname).
Application credentials secret: <this>-app (key uri, username, password, ...).
*/}}
{{- define "centrifuge-api-v4-public.cnpgClusterFullname" -}}
{{- $p := .Values.postgres }}
{{- if $p.fullnameOverride }}
{{- $p.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "postgres" $p.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-public.dbSecretName" -}}
{{- .Values.global.dbSecretName | default (printf "%s-app" (include "centrifuge-api-v4-public.cnpgClusterFullname" .)) }}
{{- end }}

{{/*
Handlers image tag used as the public schema name. latest is refused.
*/}}
{{- define "centrifuge-api-v4-public.publicSchema" -}}
{{- $tag := .Values.handlers.image.tag | default "" | toString -}}
{{- if not (regexMatch "^sha-[0-9a-f]+$" $tag) -}}
{{- fail "handlers.image.tag must be an immutable sha- tag. latest is not a schema name." -}}
{{- end -}}
{{- $tag -}}
{{- end }}

{{/*
Indexer generation the handlers consumer reads. Required on every public release.
*/}}
{{- define "centrifuge-api-v4-public.indexGeneration" -}}
{{- $generation := index .Values.global.env "INDEX_GENERATION" | default "" | toString -}}
{{- if not (regexMatch "^id[0-9]{12}$" $generation) -}}
{{- fail "INDEX_GENERATION must match id plus 12 digits (for example id202609301918)" -}}
{{- end -}}
{{- $generation -}}
{{- end }}
