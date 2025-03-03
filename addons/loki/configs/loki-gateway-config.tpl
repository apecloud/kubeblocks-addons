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
  log_format   main '$remote_addr - $remote_user [$time_local]  $status '
        '"$request" $body_bytes_sent "$http_referer" '
        '"$http_user_agent" "$http_x_forwarded_for"';
  access_log   /dev/stderr  main;

  sendfile     on;
  tcp_nopush   on;
  resolver {{ .DNS_SERVICE }}.{{ .DNS_NAMESPACE }}.svc.{{ .clusterDomain }}.;

  server {
    listen             8080;
    {{- if eq .ENABLE_IPV6 "true" }}
    listen             [::]:8080;
    {{- end }}

    location = / {
      return 200 'OK';
      auth_basic off;
    }

    {{- $backendHost := printf "%s-backend" $.cluster.metadata.name }}
    {{- $readHost := printf "%s-read" $.cluster.metadata.name }}
    {{- $writeHost := printf "%s-write" $.cluster.metadata.name }}

    {{- $writeUrl    := printf "http://%s.%s.svc.%s:3100" $writeHost   $.cluster.metadata.namespace .clusterDomain }}
    {{- $readUrl     := printf "http://%s.%s.svc.%s:3100" $readHost    $.cluster.metadata.namespace .clusterDomain }}
    {{- $backendUrl  := printf "http://%s.%s.svc.%s:3100" $backendHost $.cluster.metadata.namespace .clusterDomain }}

    # Distributor
    location = /api/prom/push {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }
    location = /loki/api/v1/push {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }
    location = /distributor/ring {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }

    # Ingester
    location = /flush {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }
    location ^~ /ingester/ {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }
    location = /ingester {
      internal;        # to suppress 301
    }

    # Ring
    location = /ring {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }

    # MemberListKV
    location = /memberlist {
      proxy_pass       {{ $writeUrl }}$request_uri;
    }


    # Ruler
    location = /ruler/ring {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /api/prom/rules {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location ^~ /api/prom/rules/ {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /loki/api/v1/rules {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location ^~ /loki/api/v1/rules/ {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /prometheus/api/v1/alerts {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /prometheus/api/v1/rules {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }

    # Compactor
    location = /compactor/ring {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /loki/api/v1/delete {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /loki/api/v1/cache/generation_numbers {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }

    # IndexGateway
    location = /indexgateway/ring {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }

    # QueryScheduler
    location = /scheduler/ring {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }

    # Config
    location = /config {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }

    # QueryFrontend, Querier
    location = /api/prom/tail {
      proxy_pass       {{ $readUrl }}$request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location = /loki/api/v1/tail {
      proxy_pass       {{ $readUrl }}$request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location ^~ /api/prom/ {
      proxy_pass       {{ $readUrl }}$request_uri;
    }
    location = /api/prom {
      internal;        # to suppress 301
    }
    location ^~ /loki/api/v1/ {
      proxy_pass       {{ $readUrl }}$request_uri;
    }
    location = /loki/api/v1 {
      internal;        # to suppress 301
    }

  }
}