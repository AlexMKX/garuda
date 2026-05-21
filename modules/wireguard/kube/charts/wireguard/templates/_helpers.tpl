{{- define "wireguard.labels" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Values.name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
garuda.managed-by: helm
{{- end -}}

{{- define "wireguard.selector" -}}
app.kubernetes.io/name: wireguard
app.kubernetes.io/instance: {{ .Values.name | quote }}
{{- end -}}

{{/* Comma-separated Multus annotation: name@iface, name@iface. */}}
{{- define "wireguard.networks" -}}
{{- $items := list -}}
{{- range .Values.nic_attach -}}
{{- $items = append $items (printf "%s@%s" . .) -}}
{{- end -}}
{{- join "," $items -}}
{{- end -}}

{{/* Render frr.conf from the ospf object. */}}
{{- define "wireguard.frrConf" -}}
{{- with .Values.ospf }}
{{- $interfaces := .interfaces -}}
{{- $passive := .passive_interfaces | default (list) -}}
frr defaults traditional
log file /tmp/frr.log
{{ range $iface := $interfaces -}}
interface {{ $iface }}
 ip ospf area {{ $.Values.ospf.area | default "0.0.0.0" }}
{{ if has $iface $passive -}}
 ip ospf passive
{{ else -}}
 ip ospf hello-interval 5
 ip ospf dead-interval 15
 ip ospf mtu-ignore
{{ end -}}
{{ end -}}
router ospf
 ospf router-id {{ .router_id }}
{{ range $r := .redistribute -}}
 redistribute {{ $r }}
{{ end -}}
{{ if .default_originate -}}
 default-information originate
{{ end -}}
{{ if .extra_frr_conf -}}
{{ .extra_frr_conf }}
{{ end -}}
{{- end }}
{{- end -}}
