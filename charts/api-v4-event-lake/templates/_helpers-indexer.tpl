{{- define "centrifuge-api-v4-event-lake.indexer.fullname" -}}
{{- printf "%s-indexer" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.indexer.selectorLabels" -}}
app.kubernetes.io/name: indexer
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Pod labels carry no chart version, so a chart bump alone does not restart the
indexer (a restart re-reads Envio state but is still a needless gap).
*/}}
{{- define "centrifuge-api-v4-event-lake.indexer.podLabels" -}}
{{ include "centrifuge-api-v4-event-lake.indexer.selectorLabels" . }}
{{ include "centrifuge-api-v4-event-lake.identityLabels" . }}
{{- with .Values.image.displayTag }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- end }}

{{- define "centrifuge-api-v4-event-lake.indexer.labels" -}}
{{ include "centrifuge-api-v4-event-lake.indexer.podLabels" . }}
helm.sh/chart: {{ include "centrifuge-api-v4-event-lake.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
