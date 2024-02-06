{{- $clusterName := $.cluster.metadata.name }}

cluster.name: {{$clusterName}}

http.cors.enabled: true
http.cors.allow-origin: "*"
http.cors.allow-headers: Authorization,X-Requested-With,Content-Type,Content-Length

discovery.type: multi-node

http:
  port: "9200"
path:
  data: /bitnami/elasticsearch/data
transport:
  port: "9300"
network:
  host: x-master-0.x-master-headless.default.svc.cluster.local
  publish_host: x-master-0.x-master-headless.default.svc.cluster.local
  bind_host: 0.0.0.0
cluster:
  name: x
  initial_master_nodes: x-master-0
node:
  name: x-master-0
  roles: master
discovery:
  seed_hosts:
    - x-master
    - x-data
    - x-ingest
    - x-coordinating
  initial_state_timeout: 10m
xpack:
  security:
    enabled: "false"
  ml:
    enabled: "false"