# cluster server list
{{- printf "\n" }}
{{- $fqnds := splitList "," .ZOOKEEPER_POD_FQDN_LIST }}
{{- range $i, $fqdn := $fqnds }}
  {{- $name := index (splitList "." $fqdn) 0 }}
  {{- $tokens := splitList "-" $name }}
  {{- $ordinal := index $tokens (sub (len $tokens) 1) }}
  {{- if ge $i 3 }}
    {{- printf "server.%s=%s:2888:3888:observer\n" $ordinal $fqdn }}
  {{- else }}
    {{- printf "server.%s=%s:2888:3888:participant\n" $ordinal $fqdn }}
  {{- end }}
{{- end }}