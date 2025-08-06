{{/*
Define load balancer annotations
*/}}
{{- define "kblib.loadBalancerAnnotations" }}
{{- if eq .Values.extra.cloudProvider "aws" }}
annotations:
  service.beta.kubernetes.io/aws-load-balancer-type: nlb
  {{- if .Values.extra.publiclyAccessible }}
  service.beta.kubernetes.io/aws-load-balancer-internal: "false"
  {{- else }}
  service.beta.kubernetes.io/aws-load-balancer-internal: "true"
  {{- end }}
{{- else if and (eq .Values.extra.cloudProvider "gcloud") .Values.extra.publiclyAccessible }}
annotations:
  networking.gke.io/load-balancer-type: Internal
{{- else if eq .Values.extra.cloudProvider "aliyun" }}
annotations:
  {{- if .Values.extra.publiclyAccessible }}
  service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: internet
  {{- else }}
  service.beta.kubernetes.io/alibaba-cloud-loadbalancer-address-type: intranet
  {{- end }}
{{- else if eq .Values.extra.cloudProvider "azure" }}
annotations:
  {{- if .Values.extra.publiclyAccessible }}
  service.beta.kubernetes.io/azure-load-balancer-internal: "false"
  {{- else }}
  service.beta.kubernetes.io/azure-load-balancer-internal: "true"
  {{- end }}
{{- else if and (eq .Values.extra.cloudProvider "huawei") (not .Values.extra.publiclyAccessible) }}
annotations:
  kubernetes.io/elb.autocreate: '{"type":"inner", "name": "A-location-d-test"}'
{{- else if eq .Values.extra.cloudProvider "oracle" }}
annotations:
  {{- if .Values.extra.publiclyAccessible }}
  oci.oraclecloud.com/load-balancer-type: nlb
  {{- else }}
  oci.oraclecloud.com/load-balancer-type: nlb
  service.beta.kubernetes.io/oci-load-balancer-internal: "true"
  {{- end }}
{{- end }}
{{- end }}