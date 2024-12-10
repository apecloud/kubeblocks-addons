{{/*
Expand the name of the chart.
*/}}
{{- define "loki.name" -}}
{{- $default := ternary "enterprise-logs" "loki" .Values.enterprise.enabled }}
{{- coalesce .Values.nameOverride $default | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "loki.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := include "loki.name" . }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "loki.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "loki.labels" -}}
helm.sh/chart: {{ include "loki.chart" . }}
{{ include "loki.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "loki.selectorLabels" -}}
app.kubernetes.io/name: {{ include "loki.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "loki.annotations" -}}
helm.sh/resource-policy: keep
{{ include "loki.apiVersion" . }}
{{- end }}

{{/*
API version annotation
*/}}
{{- define "loki.apiVersion" -}}
kubeblocks.io/crd-api-version: apps.kubeblocks.io/v1
{{- end }}

{{/*
Base template for building docker image reference
*/}}
{{- define "loki.baseImage" }}
{{- $registry := .global.registry | default .service.registry -}}
{{- $repository := .service.repository -}}
{{- $tag := .service.tag | default .defaultVersion | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end -}}

{{/*
Docker image name for Loki
*/}}
{{- define "loki.lokiImage" -}}
{{- $dict := dict "service" .Values.loki.image "global" .Values.global.image "defaultVersion" .Chart.AppVersion -}}
{{- include "loki.baseImage" $dict -}}
{{- end -}}

{{/*
Docker image name for enterprise logs
*/}}
{{- define "loki.enterpriseImage" -}}
{{- $dict := dict "service" .Values.enterprise.image "global" .Values.global.image "defaultVersion" .Values.enterprise.version -}}
{{- include "loki.baseImage" $dict -}}
{{/* {{- printf "foo" -}} */}}
{{- end -}}

{{/*
Docker image name
*/}}
{{- define "loki.image" -}}
{{- if .Values.enterprise.enabled -}}{{- include "loki.enterpriseImage" . -}}{{- else -}}{{- include "loki.lokiImage" . -}}{{- end -}}
{{- end -}}


{{/*
Memcached Docker image
*/}}
{{- define "loki.memcachedImage" -}}
{{- $dict := dict "service" .Values.memcached.image "global" .Values.global.image -}}
{{- include "loki.image" $dict -}}
{{- end }}

{{/*
Memcached Exporter Docker image
*/}}
{{- define "loki.memcachedExporterImage" -}}
{{- $dict := dict "service" .Values.memcachedExporter.image "global" .Values.global.image -}}
{{- include "loki.image" $dict -}}
{{- end }}
{{/* Snippet for the nginx file used by gateway */}}
{{- define "loki.nginxFile" }}
worker_processes  5;  ## Default: 1
error_log  /dev/stderr;
pid        /tmp/nginx.pid;
worker_rlimit_nofile 8192;

events {
  worker_connections  4096;  ## Default: 1024
}

http {
  client_body_temp_path /tmp/client_temp;
  proxy_temp_path       /tmp/proxy_temp_path;
  fastcgi_temp_path     /tmp/fastcgi_temp;
  uwsgi_temp_path       /tmp/uwsgi_temp;
  scgi_temp_path        /tmp/scgi_temp;

  client_max_body_size  4M;

  proxy_read_timeout    600; ## 10 minutes
  proxy_send_timeout    600;
  proxy_connect_timeout 600;

  proxy_http_version    1.1;

  default_type application/octet-stream;
  log_format   {{ .Values.gateway.nginxConfig.logFormat }}

  {{- if .Values.gateway.verboseLogging }}
  access_log   /dev/stderr  main;
  {{- else }}

  map $status $loggable {
    ~^[23]  0;
    default 1;
  }
  access_log   /dev/stderr  main  if=$loggable;
  {{- end }}

  sendfile     on;
  tcp_nopush   on;
  {{- if .Values.gateway.nginxConfig.resolver }}
  resolver {{ .Values.gateway.nginxConfig.resolver }};
  {{- else }}
  resolver {{ .Values.global.dnsService }}.{{ .Values.global.dnsNamespace }}.svc.{{ .Values.global.clusterDomain }}.;
  {{- end }}

  {{- with .Values.gateway.nginxConfig.httpSnippet }}
  {{- tpl . $ | nindent 2 }}
  {{- end }}

  server {
    {{- if (.Values.gateway.nginxConfig.ssl) }}
    listen             8080 ssl;
    {{- if .Values.gateway.nginxConfig.enableIPv6 }}
    listen             [::]:8080 ssl;
    {{- end }}
    {{- else }}
    listen             8080;
    {{- if .Values.gateway.nginxConfig.enableIPv6 }}
    listen             [::]:8080;
    {{- end }}
    {{- end }}

    {{- if .Values.gateway.basicAuth.enabled }}
    auth_basic           "Loki";
    auth_basic_user_file /etc/nginx/secrets/.htpasswd;
    {{- end }}

    location = / {
      return 200 'OK';
      auth_basic off;
    }
    ########################################################
    # Configure backend targets

    {{- $backendHost := include "loki.backendFullname" .}}
    {{- $readHost := include "loki.readFullname" .}}
    {{- $writeHost := include "loki.writeFullname" .}}

    {{- if .Values.read.legacyReadTarget }}
    {{- $backendHost = include "loki.readFullname" . }}
    {{- end }}

    {{- $httpSchema := .Values.gateway.nginxConfig.schema }}

    {{- $writeUrl    := printf "%s://%s.%s.svc.%s:%s" $httpSchema $writeHost   .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $readUrl     := printf "%s://%s.%s.svc.%s:%s" $httpSchema $readHost    .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $backendUrl  := printf "%s://%s.%s.svc.%s:%s" $httpSchema $backendHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}

    {{- if .Values.gateway.nginxConfig.customWriteUrl }}
    {{- $writeUrl  = .Values.gateway.nginxConfig.customWriteUrl }}
    {{- end }}
    {{- if .Values.gateway.nginxConfig.customReadUrl }}
    {{- $readUrl = .Values.gateway.nginxConfig.customReadUrl }}
    {{- end }}
    {{- if .Values.gateway.nginxConfig.customBackendUrl }}
    {{- $backendUrl = .Values.gateway.nginxConfig.customBackendUrl }}
    {{- end }}

    {{- $singleBinaryHost := include "loki.singleBinaryFullname" . }}
    {{- $singleBinaryUrl  := printf "%s://%s.%s.svc.%s:%s" $httpSchema $singleBinaryHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}

    {{- $distributorHost := include "loki.distributorFullname" .}}
    {{- $ingesterHost := include "loki.ingesterFullname" .}}
    {{- $queryFrontendHost := include "loki.queryFrontendFullname" .}}
    {{- $indexGatewayHost := include "loki.indexGatewayFullname" .}}
    {{- $rulerHost := include "loki.rulerFullname" .}}
    {{- $compactorHost := include "loki.compactorFullname" .}}
    {{- $schedulerHost := include "loki.querySchedulerFullname" .}}


    {{- $distributorUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $distributorHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) -}}
    {{- $ingesterUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $ingesterHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $queryFrontendUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $queryFrontendHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $indexGatewayUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $indexGatewayHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $rulerUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $rulerHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $compactorUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $compactorHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $schedulerUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $schedulerHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}

    {{- if eq (include "loki.deployment.isSingleBinary" .) "true"}}
    {{- $distributorUrl = $singleBinaryUrl }}
    {{- $ingesterUrl = $singleBinaryUrl }}
    {{- $queryFrontendUrl = $singleBinaryUrl }}
    {{- $indexGatewayUrl = $singleBinaryUrl }}
    {{- $rulerUrl = $singleBinaryUrl }}
    {{- $compactorUrl = $singleBinaryUrl }}
    {{- $schedulerUrl = $singleBinaryUrl }}
    {{- else if eq (include "loki.deployment.isScalable" .) "true"}}
    {{- $distributorUrl = $writeUrl }}
    {{- $ingesterUrl = $writeUrl }}
    {{- $queryFrontendUrl = $readUrl }}
    {{- $indexGatewayUrl = $backendUrl }}
    {{- $rulerUrl = $backendUrl }}
    {{- $compactorUrl = $backendUrl }}
    {{- $schedulerUrl = $backendUrl }}
    {{- end -}}

    # Distributor
    location = /api/prom/push {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }
    location = /loki/api/v1/push {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }
    location = /distributor/ring {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }
    location = /otlp/v1/logs {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }

    # Ingester
    location = /flush {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }
    location ^~ /ingester/ {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }
    location = /ingester {
      internal;        # to suppress 301
    }

    # Ring
    location = /ring {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }

    # MemberListKV
    location = /memberlist {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }

    # Ruler
    location = /ruler/ring {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /api/prom/rules {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location ^~ /api/prom/rules/ {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /loki/api/v1/rules {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location ^~ /loki/api/v1/rules/ {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /prometheus/api/v1/alerts {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /prometheus/api/v1/rules {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }

    # Compactor
    location = /compactor/ring {
      proxy_pass       {{ $compactorUrl }}$request_uri;
    }
    location = /loki/api/v1/delete {
      proxy_pass       {{ $compactorUrl }}$request_uri;
    }
    location = /loki/api/v1/cache/generation_numbers {
      proxy_pass       {{ $compactorUrl }}$request_uri;
    }

    # IndexGateway
    location = /indexgateway/ring {
      proxy_pass       {{ $indexGatewayUrl }}$request_uri;
    }

    # QueryScheduler
    location = /scheduler/ring {
      proxy_pass       {{ $schedulerUrl }}$request_uri;
    }

    # Config
    location = /config {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }

    {{- if and .Values.enterprise.enabled .Values.enterprise.adminApi.enabled }}
    # Admin API
    location ^~ /admin/api/ {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /admin/api {
      internal;        # to suppress 301
    }
    {{- end }}


    # QueryFrontend, Querier
    location = /api/prom/tail {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location = /loki/api/v1/tail {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location ^~ /api/prom/ {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
    }
    location = /api/prom {
      internal;        # to suppress 301
    }
    location ^~ /loki/api/v1/ {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
    }
    location = /loki/api/v1 {
      internal;        # to suppress 301
    }

    {{- with .Values.gateway.nginxConfig.serverSnippet }}
    {{ . | nindent 4 }}
    {{- end }}
  }
}
{{- end }}

{{/*
singleBinary fullname
*/}}
{{- define "loki.singleBinaryFullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
write fullname
*/}}
{{- define "loki.writeFullname" -}}
{{ include "loki.name" . }}-write
{{- end }}

{{/*
read fullname
*/}}
{{- define "loki.readFullname" -}}
{{ include "loki.name" . }}-read
{{- end }}

{{/*
backend fullname
*/}}
{{- define "loki.backendFullname" -}}
{{ include "loki.name" . }}-backend
{{- end }}

{{/*
gateway fullname
*/}}
{{- define "loki.gatewayFullname" -}}
{{ include "loki.fullname" . }}-gateway
{{- end }}

{{/*
gateway common labels
*/}}
{{- define "loki.gatewayLabels" -}}
{{ include "loki.labels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
gateway selector labels
*/}}
{{- define "loki.gatewaySelectorLabels" -}}
{{ include "loki.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
gateway auth secret name
*/}}
{{- define "loki.gatewayAuthSecret" -}}
{{ .Values.gateway.basicAuth.existingSecret | default (include "loki.gatewayFullname" . ) }}
{{- end }}

{{/*
gateway Docker image
*/}}
{{- define "loki.gatewayImage" -}}
{{- $dict := dict "service" .Values.gateway.image "global" .Values.global.image -}}
{{- include "loki.baseImage" $dict -}}
{{- end }}

{{/*
gateway priority class name
*/}}
{{- define "loki.gatewayPriorityClassName" -}}
{{- $pcn := coalesce .Values.global.priorityClassName .Values.gateway.priorityClassName -}}
{{- if $pcn }}
priorityClassName: {{ $pcn }}
{{- end }}
{{- end }}

{{/*
distributor fullname
*/}}
{{- define "loki.distributorFullname" -}}
{{ include "loki.fullname" . }}-distributor
{{- end }}

{{/*
ingester fullname
*/}}
{{- define "loki.ingesterFullname" -}}
{{ include "loki.fullname" . }}-ingester
{{- end }}

{{/*
query-frontend fullname
*/}}
{{- define "loki.queryFrontendFullname" -}}
{{ include "loki.fullname" . }}-query-frontend
{{- end }}

{{/*
index-gateway fullname
*/}}
{{- define "loki.indexGatewayFullname" -}}
{{ include "loki.fullname" . }}-index-gateway
{{- end }}

{{/*
ruler fullname
*/}}
{{- define "loki.rulerFullname" -}}
{{ include "loki.fullname" . }}-ruler
{{- end }}

{{/*
compactor fullname
*/}}
{{- define "loki.compactorFullname" -}}
{{ include "loki.fullname" . }}-compactor
{{- end }}

{{/*
query-scheduler fullname
*/}}
{{- define "loki.querySchedulerFullname" -}}
{{ include "loki.fullname" . }}-query-scheduler
{{- end }}

{{/*
Define loki backend component definition name
*/}}
{{- define "loki.backendCmpdName" -}}
loki-backend-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki backend component definition regular expression name prefix
*/}}
{{- define "loki.backendCmpdRegexpPattern" -}}
^loki-backend-
{{- end -}}

{{/*
Define loki gateway component definition name
*/}}
{{- define "loki.gatewayCmpdName" -}}
loki-gateway-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki backend component definition regular expression name prefix
*/}}
{{- define "loki.gatewayCmpdRegexpPattern" -}}
^loki-gateway-
{{- end -}}

{{/*
Define loki read component definition name
*/}}
{{- define "loki.readCmpdName" -}}
loki-read-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki read component definition regular expression name prefix
*/}}
{{- define "loki.readCmpdRegexpPattern" -}}
^loki-read-
{{- end -}}


{{/*
Define loki write component definition name
*/}}
{{- define "loki.writeCmpdName" -}}
loki-write-{{ .Chart.Version }}
{{- end -}}

{{/*
Define loki write component definition regular expression name prefix
*/}}
{{- define "loki.writeCmpdRegexpPattern" -}}
^loki-write-
{{- end -}}
