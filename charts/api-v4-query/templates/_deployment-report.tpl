{{- define "centrifuge-api-v4-query.deploymentReportEnv" -}}
- name: REPORT_STATE
  value: {{ .state | quote }}
- name: REPORT_TASK
  value: {{ .root.Values.deploymentReport.task | quote }}
- name: REPORT_TRANSITION
  value: {{ .root.Values.deploymentReport.transition | quote }}
- name: REPORT_ENVIRONMENT
  value: {{ .root.Values.environment | quote }}
- name: REPORT_COMPONENT
  value: {{ .root.Values.deploymentReport.component | quote }}
- name: REPORT_PRODUCTION_ENVIRONMENT
  value: {{ if hasPrefix "main-" .root.Values.environment }}"true"{{ else }}"false"{{ end }}
- name: REPORT_PROJECTION_ID
  value: {{ .root.Values.projectionId | quote }}
- name: REPORT_QUERY_ID
  value: {{ .root.Values.id | quote }}
- name: REPORT_SOURCE_COMMIT
  value: {{ .root.Values.deploymentReport.sourceCommit | quote }}
- name: REPORT_IMAGE_DIGEST
  value: {{ .root.Values.image.digest | quote }}
- name: REPORT_CHART_NAME
  value: {{ .root.Values.deploymentReport.chart.name | quote }}
- name: REPORT_CHART_VERSION
  value: {{ .root.Values.deploymentReport.chart.version | quote }}
- name: REPORT_CHART_DIGEST
  value: {{ .root.Values.deploymentReport.chart.digest | quote }}
{{- if .root.Values.deploymentReport.argoExternalUrl }}
- name: REPORT_LOG_URL
  value: {{ printf "%s/applications/argo/cfg-api-v4-%s-%s" .root.Values.deploymentReport.argoExternalUrl .root.Values.environment .root.Values.id | quote }}
{{- end }}
{{- $previewHost := include "centrifuge-api-v4-query.previewHost" .root | trim -}}
{{- $previewNetwork := include "centrifuge-api-v4-query.previewNetwork" .root | trim -}}
{{- if and $previewHost $previewNetwork .root.Values.id }}
- name: REPORT_ENVIRONMENT_URL
  value: {{ printf "https://%s/%s/%s" $previewHost $previewNetwork (trimPrefix "q-" .root.Values.id) | quote }}
{{- end }}
- name: GITHUB_APP_ID
  valueFrom:
    secretKeyRef:
      name: {{ .root.Values.deploymentReport.githubDeploymentsSecretName | quote }}
      key: app-id
- name: GITHUB_INSTALLATION_ID
  valueFrom:
    secretKeyRef:
      name: {{ .root.Values.deploymentReport.githubDeploymentsSecretName | quote }}
      key: installation-id
- name: GITHUB_PRIVATE_KEY_PATH
  value: /etc/github/private-key.pem
{{- end }}
