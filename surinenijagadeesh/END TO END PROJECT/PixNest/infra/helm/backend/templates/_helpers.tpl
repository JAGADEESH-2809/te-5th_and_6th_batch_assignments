{{/* Fixed name so other charts can reference the Service by convention. */}}
{{- define "backend.fullname" -}}
{{- default "pixnest-backend" .Values.fullnameOverride -}}
{{- end -}}

{{- define "backend.labels" -}}
app.kubernetes.io/name: {{ include "backend.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: pixnest
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/* Selector uses only the stable name label (release-independent, cross-chart friendly). */}}
{{- define "backend.selectorLabels" -}}
app.kubernetes.io/name: {{ include "backend.fullname" . }}
{{- end -}}

{{/* DATABASE_URL: explicit value if given, else built from the database section. */}}
{{- define "backend.databaseUrl" -}}
{{- if .Values.databaseUrl -}}
{{ .Values.databaseUrl }}
{{- else -}}
postgresql+asyncpg://{{ .Values.database.username }}:{{ .Values.database.password }}@{{ .Values.database.host }}:{{ .Values.database.port }}/{{ .Values.database.name }}
{{- end -}}
{{- end -}}

