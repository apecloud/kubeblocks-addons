{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $fe_component := fromJson "{}" }}
{{- range $i, $e := $.cluster.spec.componentSpecs }}
  {{- if or (eq $e.componentDef "starrocks-fe-sd") (eq $e.componentDef "starrocks-fe-sn") }}
  {{- $fe_component = $e }}
  {{- end }}
{{- end }}
{{- $fe_service := printf "%s-%s-fe" $clusterName $fe_component.name }}

pid   /tmp/nginx.pid;
worker_processes 4;
include /usr/share/nginx/modules/*.conf;
events {
  worker_connections 256;
}

http {
  sendfile            on;
  tcp_nopush          on;
  tcp_nodelay         on;
  keepalive_timeout   65;
  types_hash_max_size 2048;
  client_max_body_size 0;
  ignore_invalid_headers off;
  underscores_in_headers on;
  proxy_read_timeout 600s;

  client_body_temp_path /tmp/client_temp;
  proxy_temp_path       /tmp/proxy_temp_path;
  fastcgi_temp_path     /tmp/fastcgi_temp;
  uwsgi_temp_path       /tmp/uwsgi_temp;
  scgi_temp_path        /tmp/scgi_temp;

  default_type        application/octet-stream;

  server {
    listen 8080;
    listen [::]:8080;
    proxy_intercept_errors on;
    recursive_error_pages on;

    location /nginx/health {
      access_log off;
      return 200;
    }

    location / {
      proxy_pass http://{{ $fe_service }}:8030;
      proxy_set_header Expect $http_expect;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      error_page 307 = @handle_redirect;
    }

    location /api/transaction/load {
      proxy_pass http://{{ $fe_service }}:8030;
      proxy_pass_request_body off;
      proxy_set_header Expect $http_expect;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      error_page 307 = @handle_redirect;
    }

    location ~ ^/api/.*/.*/_stream_load$ {
      proxy_pass http://{{ $fe_service }}:8030;
      proxy_pass_request_body off;
      proxy_set_header Expect $http_expect;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      error_page 307 = @handle_redirect;
    }

    location @handle_redirect {
      if ($upstream_http_location ~ "{{ $fe_service }}") {
        rewrite ^ /_redirect_to_fe last;
      }
      if ($upstream_http_location !~ "{{ $fe_service }}") {
        rewrite ^ /_redirect_to_others last;
      }
    }

    location /_redirect_to_fe {
      set $redirect_uri '$upstream_http_location';
      proxy_pass $redirect_uri;
      proxy_set_header Expect $http_expect;
      proxy_pass_request_body off;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      error_page 307 = @handle_redirect;
    }

    location /_redirect_to_others {
      set $redirect_uri '$upstream_http_location';
      proxy_pass $redirect_uri;
      proxy_set_header Expect $http_expect;
      proxy_pass_request_body on;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      error_page 307 = @handle_redirect;
    }
  }
}