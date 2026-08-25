{{/*
Name for our own resources (the bootstrap Jobs).

Deliberately NOT `.Chart.Name`: the upstream Redpanda Service selects on
`app.kubernetes.io/name: redpanda` plus the release instance only, with no
component label. Reusing `redpanda` here would put a running bootstrap Job pod
behind the Kafka / Schema Registry / Admin Services, where it answers nothing.
*/}}
{{- define "centrifuge-redpanda.name" -}}
{{- default (printf "%s-bootstrap" .Chart.Name) .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "centrifuge-redpanda.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := .Chart.Name }}
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
{{- define "centrifuge-redpanda.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "centrifuge-redpanda.labels" -}}
helm.sh/chart: {{ include "centrifuge-redpanda.chart" . }}
{{ include "centrifuge-redpanda.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "centrifuge-redpanda.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-redpanda.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
In-cluster Kafka brokers used by bootstrap Jobs.
*/}}
{{- define "centrifuge-redpanda.brokers" -}}
{{- .Values.bootstrap.brokers | default "cfg-api-redpanda:9093" -}}
{{- end }}

{{/*
In-cluster Schema Registry URL used by bootstrap Jobs.
*/}}
{{- define "centrifuge-redpanda.schemaRegistryUrl" -}}
{{- .Values.bootstrap.schemaRegistryUrl | default "http://cfg-api-redpanda:8081" -}}
{{- end }}

{{/*
rpk image for topic bootstrap. Tag defaults to this chart's appVersion, which
tracks the vendored Redpanda subchart so the rpk client matches the brokers.
*/}}
{{- define "centrifuge-redpanda.topicsImage" -}}
{{- $tag := .Values.bootstrap.topics.image.tag | default .Chart.AppVersion -}}
{{- printf "%s:%s" .Values.bootstrap.topics.image.repository $tag -}}
{{- end }}
