{{- define "centrifuge-api-v4-database.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-database.selectorLabels" -}}
app.kubernetes.io/name: {{ include "centrifuge-api-v4-database.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "centrifuge-api-v4-database.labels" -}}
{{ include "centrifuge-api-v4-database.selectorLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cfg-api-v4
api-v4.centrifuge.io/environment: {{ .Values.environment | quote }}
api-v4.centrifuge.io/component: {{ printf "database-%s" .Values.kind | quote }}
{{- end }}

{{/*
The CNPG Cluster name is set explicitly by GitOps (postgres.fullnameOverride) so
that workloads can reference <cluster>-app without re-deriving the subchart's
naming rules.
*/}}
{{- define "centrifuge-api-v4-database.clusterName" -}}
{{- .Values.postgres.fullnameOverride }}
{{- end }}

{{- define "centrifuge-api-v4-database.sqlRoPoolerName" -}}
{{- printf "%s-pooler-%s" (include "centrifuge-api-v4-database.clusterName" .) .Values.sqlRo.pooler.name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Cross-field rules that values.schema.json cannot express.
*/}}
{{- define "centrifuge-api-v4-database.validate" -}}
{{- if .Values.sqlRo.enabled }}
{{- $altNames := .Values.postgres.cluster.certificates.serverAltDNSNames | default list }}
{{- if not (has .Values.sqlRo.hostname $altNames) }}
{{- fail (printf "sqlRo.hostname %s must be listed in postgres.cluster.certificates.serverAltDNSNames, or hostssl clients cannot verify the server" .Values.sqlRo.hostname) }}
{{- end }}
{{- end }}
{{- end }}
