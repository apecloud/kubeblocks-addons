## This is dynamic configuration file for camellia redis proxy
## when camellia-redis-proxy.proxy-dynamic-conf-loader-class-name defined in application.yaml is com.netease.nim.camellia.redis.proxy.conf.FileBasedProxyDynamicConfLoader then this file will be loaded
## the default configuration file name is camellia-redis-proxy.properties

## Configuration for multi-tenant proxies

#  ## provided for DynamicConfProxyRouteConfUpdater
#  1.default.route.conf=redis://@127.0.0.1:6379
#  2.default.route.conf=redis-cluster://@127.0.0.1:6380,127.0.0.1:6381,127.0.0.1:6382
#  3.default.route.conf={"type": "simple","operation": {"read": "redis://passwd123@127.0.0.1:6379","type": "rw_separate","write": "redis-sentinel://passwd2@127.0.0.1:6379,127.0.0.1:6378/master"}}
#
#  ## provided for DynamicConfClientAuthProvider
#  password123.auth.conf=1|default
#  password456.auth.conf=2|default
#  password789.auth.conf=3|default


## Another Configuration for multi-tenant proxies
#  ## This is an array where each item represents a route, supporting multiple sets of routes.
#  multi.tenant.route.config=[{"name":"route1", "password": "passwd1", "route": "redis://passxx@127.0.0.1:16379"},{"name":"route2", "password": "passwd2", "route": "redis-cluster://@127.0.0.1:6380,127.0.0.1:6381,127.0.0.1:6382"},{"name":"route3", "password": "passwd3", "route": {"type": "simple","operation": {"read": "redis://passwd123@127.0.0.1:6379","type": "rw_separate","write": "redis-sentinel://passwd2@127.0.0.1:6379,127.0.0.1:6378/master"}}}]
