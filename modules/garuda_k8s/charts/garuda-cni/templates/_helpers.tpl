{{/* Common labels rendered on every resource. */}}
{{- define "garuda.labels" -}}
app.kubernetes.io/name: garuda-cni
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
garuda.managed-by: helm
{{- end -}}
