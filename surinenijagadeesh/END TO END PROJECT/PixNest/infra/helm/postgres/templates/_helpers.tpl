{{/* Fixed name so the backend chart can reach the Service by convention. */}}
{{- define "postgres.fullname" -}}
{{- default "pixnest-postgres" .Values.fullnameOverride -}}
{{- end -}}

{{- define "postgres.labels" -}}
app.kubernetes.io/name: {{ include "postgres.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: pixnest
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres.fullname" . }}
{{- end -}}

