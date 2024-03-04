## This is dynamic configuration file for camellia-redis-proxy backend redis resources with json format

## the supported backend redis resources can be referred here: https://github.com/netease-im/camellia/blob/master/docs/redis-proxy/auth/redis-resources.md
## and the example of backend resource configuration can be referred here: https://github.com/netease-im/camellia/blob/master/docs/redis-proxy/auth/complex.md

## for example:
## {
#    "type": "simple",
#    "operation": {
#        "read": "redis://passwd123@127.0.0.1:6379",
#        "type": "rw_separate",
#        "write": "redis-sentinel://passwd2@127.0.0.1:6379,127.0.0.1:6378/master"
#    }
# }

## config a redis backend resource, replace it with your own redis resource
redis://passwd@127.0.0.1:6379