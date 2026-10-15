{{- define "centrifuge-api-v4-routes.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-routes.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Short Service suffix: staging -s, production none, rollback -r.
*/}}
{{- define "centrifuge-api-v4-routes.serviceName" -}}
{{- $role := .role -}}
{{- if eq $role "production" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else if eq $role "staging" -}}
{{- printf "%s-s" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else if eq $role "rollback" -}}
{{- printf "%s-r" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- fail (printf "unknown routes role %q" $role) -}}
{{- end -}}
{{- end }}

{{/*
Traefik Middleware reference for router.middlewares (namespace-name@kubernetescrd).
*/}}
{{- define "centrifuge-api-v4-routes.middlewareRef" -}}
{{- printf "%s-%s@kubernetescrd" .Release.Namespace .middlewareName -}}
{{- end }}

{{- define "centrifuge-api-v4-routes.labels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-routes.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: cfg-api-v4
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: routes
{{- end }}
