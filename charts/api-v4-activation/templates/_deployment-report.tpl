{{- define "centrifuge-api-v4-activation.deploymentReportEnv" -}}
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
- name: REPORT_OPERATION_ID
  value: {{ .root.Values.operation.operationId | quote }}
- name: REPORT_PROJECTION_ID
  value: {{ .root.Values.operation.desiredProjection | quote }}
- name: REPORT_ACTIVATION_COMMAND
  value: {{ .root.Values.operation.command | quote }}
- name: REPORT_IMAGE_DIGEST
  value: {{ .root.Values.image.digest | quote }}
- name: REPORT_CHART_NAME
  value: {{ .root.Values.deploymentReport.chart.name | quote }}
- name: REPORT_CHART_VERSION
  value: {{ .root.Values.deploymentReport.chart.version | quote }}
{{- if .root.Values.deploymentReport.chart.digest }}
- name: REPORT_CHART_DIGEST
  value: {{ .root.Values.deploymentReport.chart.digest | quote }}
{{- end }}
{{- if .root.Values.deploymentReport.argoExternalUrl }}
{{- $argo := printf "%s/applications/argo/cfg-api-v4-routes-%s" .root.Values.deploymentReport.argoExternalUrl .root.Values.environment }}
- name: REPORT_LOG_URL
  value: {{ $argo | quote }}
- name: REPORT_ENVIRONMENT_URL
  value: {{ $argo | quote }}
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
