## This is application.yml configuration file for camellia-redis-proxy

## Default dynamic configuration example for multi-tenant proxy configuration
## refer: https://github.com/netease-im/camellia/blob/master/docs/redis-proxy/other/multi-telant2.md
## you need to provide a properties file (default is camellia-redis-proxy.properties) for dynamic configuration.
server:
  port: 6380
spring:
  application:
    name: camellia-redis-proxy-server

camellia-redis-proxy:
  console-port: 16379
  monitor-enable: false
  monitor-interval-seconds: 60
  plugins:
    - monitorPlugin
    - bigKeyPlugin
    - hotKeyPlugin
  client-auth-provider-class-name: com.netease.nim.camellia.redis.proxy.auth.MultiTenantClientAuthProvider
  transpond:
    type: custom
    custom:
      proxy-route-conf-updater-class-name: com.netease.nim.camellia.redis.proxy.route.MultiTenantProxyRouteConfUpdater
#
#  the mapping camellia-redis-proxy.properties file content, that is an array where each item represents a route, supporting multiple sets of routes:
#  multi.tenant.route.config=[{"name":"route1", "password": "passwd1", "route": "redis://passxx@127.0.0.1:16379"},{"name":"route2", "password": "passwd2", "route": "redis-cluster://@127.0.0.1:6380,127.0.0.1:6381,127.0.0.1:6382"},{"name":"route3", "password": "passwd3", "route": {"type": "simple","operation": {"read": "redis://passwd123@127.0.0.1:6379","type": "rw_separate","write": "redis-sentinel://passwd2@127.0.0.1:6379,127.0.0.1:6378/master"}}}]


## dynamic configuration for a single-tenant proxy with a local redis backend with json-file format
## refer: https://github.com/netease-im/camellia/blob/master/docs/redis-proxy/other/dynamic-conf.md
##
#server:
#  port: 6380
#spring:
#  application:
#    name: camellia-redis-proxy-server
#
#camellia-redis-proxy:
#  console-port: 16379                           # console port, default 16379, if setting -16379, proxy will choose a random port, if setting 0, will disable console
#  password: pass123                             # password of proxy, priority less than custom client-auth-provider-class-name
#  monitor-enable: false                         # monitor enable/disable configure
#  monitor-interval-seconds: 60                  # monitor data refresh interval seconds
#  plugins:                                      # plugin list
#    - monitorPlugin
#    - bigKeyPlugin
#    - hotKeyPlugin
#  proxy-dynamic-conf-loader-class-name: com.netease.nim.camellia.redis.proxy.conf.FileBasedProxyDynamicConfLoader
#  config:
#    "dynamic.conf.file.path": "camellia-redis-proxy.properties"
#  transpond:
#    type: local                                 # local、remote、custom, local type does not support multi-tenant.
#    local:
#      type: complex                             # simple、complexze
#      dynamic: true                             # dynamic load conf
#      check-interval-millis: 3000               # dynamic conf check interval seconds
#      json-file: "resource-table.json"          # backend redis resources json file

## Another configuration for camellia-redis-proxy under a multi-tenant mode.
## refer: https://github.com/netease-im/camellia/blob/master/docs/redis-proxy/other/multi-telant.md
## you need to provide a properties file (default is camellia-redis-proxy.properties) for dynamic configuration.
#
# server:
#   port: 6380
# spring:
#   application:
#     name: camellia-redis-proxy-server
#
# camellia-redis-proxy:
#   console-port: 16379
#   monitor-enable: false
#   monitor-interval-seconds: 60
#   plugins:
#     - monitorPlugin
#     - bigKeyPlugin
#     - hotKeyPlugin
#   client-auth-provider-class-name: com.netease.nim.camellia.redis.proxy.auth.DynamicConfClientAuthProvider
#   transpond:
#     type: custom
#     custom:
#       proxy-route-conf-updater-class-name: com.netease.nim.camellia.redis.proxy.route.DynamicConfProxyRouteConfUpdater
#
#  the mapping camellia-redis-proxy.properties file content:
#
#  ## provided for DynamicConfProxyRouteConfUpdater
#  1.default.route.conf=redis://@127.0.0.1:6379
#  2.default.route.conf=redis-cluster://@127.0.0.1:6380,127.0.0.1:6381,127.0.0.1:6382
#  3.default.route.conf={"type": "simple","operation": {"read": "redis://passwd123@127.0.0.1:6379","type": "rw_separate","write": "redis-sentinel://passwd2@127.0.0.1:6379,127.0.0.1:6378/master"}}
#
#  ## provided for DynamicConfClientAuthProvider
#  password123.auth.conf=1|default
#  password456.auth.conf=2|default
#  password789.auth.conf=3|default









