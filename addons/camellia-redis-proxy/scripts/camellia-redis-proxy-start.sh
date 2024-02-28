#!/bin/sh
set -ex

java -XX:+UseG1GC -Xms4096m -Xmx4096m -Dio.netty.tryReflectionSetAccessible=true \
-Dspring.config.location="${CAMELLIA_REDIS_PROXY_APPLICATION_CONFIG}" \
-Ddynamic.conf.file.path="${CAMELLIA_REDIS_PROXY_PROPERTIES_CONFIG}" \
--add-opens java.base/java.lang=ALL-UNNAMED \
--add-opens java.base/java.io=ALL-UNNAMED \
--add-opens java.base/java.math=ALL-UNNAMED \
--add-opens java.base/java.net=ALL-UNNAMED \
--add-opens java.base/java.nio=ALL-UNNAMED \
--add-opens java.base/java.security=ALL-UNNAMED \
--add-opens java.base/java.text=ALL-UNNAMED \
--add-opens java.base/java.time=ALL-UNNAMED \
--add-opens java.base/java.util=ALL-UNNAMED \
--add-opens java.base/jdk.internal.access=ALL-UNNAMED \
--add-opens java.base/jdk.internal.misc=ALL-UNNAMED \
--add-opens java.base/sun.net.util=ALL-UNNAMED \
-server org.springframework.boot.loader.launch.JarLauncher

