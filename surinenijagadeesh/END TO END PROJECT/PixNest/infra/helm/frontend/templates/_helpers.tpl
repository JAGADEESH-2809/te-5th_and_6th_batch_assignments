{{/* Fixed name so other charts can reference the Service by convention. */}}
{{- define "frontend.fullname" -}}
{{- default "pixnest-frontend" .Values.fullnameOverride -}}
{{- end -}}

{{- define "frontend.labels" -}}
app.kubernetes.io/name: {{ include "frontend.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: pixnest
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Selector uses only the stable name label (release-independent, cross-chart friendly). */}}
{{- define "frontend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "frontend.fullname" . }}
{{- end -}}

