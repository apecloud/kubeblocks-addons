[peers]
{{- $prefix := printf "%s-" .PGBOUNCER_COMPONENT_NAME }}
{{- range $fqdn := compact (splitList "," .PGBOUNCER_POD_FQDNS) }}
{{- $pod := first (splitList "." $fqdn) }}
{{- $ordinal := trimPrefix $prefix $pod }}
{{- if or (not (regexMatch "^(0|[1-9][0-9]*)$" $ordinal)) (ge (atoi $ordinal) 65535) }}
{{- fail "PgBouncer peering requires default instance names with ordinals in 0..65534" }}
{{- end }}
{{ add1 (atoi $ordinal) }} = host={{ $fqdn }} port=6432
{{- end }}
