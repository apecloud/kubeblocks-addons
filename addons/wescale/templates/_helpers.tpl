{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "apecloud-mysql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "apecloud-mysql.spec.runtime.vtablet" -}}
ports:
  - containerPort: 15100
    name: vttabletport
  - containerPort: 16100
    name: vttabletgrpc
env:
  - name: CELL
    value: {{ .Values.wesqlscale.cell | default "zone1" | quote }}
  - name: VTTABLET_PORT
    value: "15100"
  - name: VTTABLET_GRPC_PORT
  - name: VTCTLD_HOST
    value: "$(KB_CLUSTER_NAME)-wescale-ctrl-headless"
  - name: VTCTLD_WEB_PORT
    value: "15000"
  - name: SERVICE_PORT
    value: "$(VTTABLET_PORT)"
command: ["/scripts/vttablet.sh"]
volumeMounts:
  - name: scripts
    mountPath: /scripts
  - name: mysql-scale-config
    mountPath: /conf
  - name: data
    mountPath: /vtdataroot
{{- end }}
