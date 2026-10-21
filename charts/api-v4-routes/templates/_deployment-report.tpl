{{- define "centrifuge-api-v4-routes.deploymentReportEnv" -}}
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
- name: REPORT_STAGING_QUERY
  value: {{ .root.Values.stagingQuery | quote }}
- name: REPORT_PRODUCTION_QUERY
  value: {{ .root.Values.productionQuery | quote }}
- name: REPORT_ROLLBACK_QUERY
  value: {{ .root.Values.rollbackQuery | quote }}
- name: REPORT_CHART_NAME
  value: {{ .root.Values.deploymentReport.chart.name | quote }}
- name: REPORT_CHART_VERSION
  value: {{ .root.Values.deploymentReport.chart.version | quote }}
{{- if .root.Values.deploymentReport.chart.digest }}
- name: REPORT_CHART_DIGEST
  value: {{ .root.Values.deploymentReport.chart.digest | quote }}
{{- end }}
{{- if .root.Values.deploymentReport.environmentUrl }}
- name: REPORT_ENVIRONMENT_URL
  value: {{ .root.Values.deploymentReport.environmentUrl | quote }}
{{- end }}
{{- if .root.Values.deploymentReport.argoExternalUrl }}
- name: REPORT_LOG_URL
  value: {{ printf "%s/applications/argo/cfg-api-v4-routes-%s" .root.Values.deploymentReport.argoExternalUrl .root.Values.environment | quote }}
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
