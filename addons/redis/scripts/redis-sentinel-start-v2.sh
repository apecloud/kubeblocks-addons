#!/bin/sh
set -ex

# Based on the Component Definition API, Redis Sentinel deployed independently

echo "start to setup redis sentinel conf"
mkdir -p /data/sentinel
if [ -f /data/sentinel/redis-sentinel.conf ]; then
  sed -i "/sentinel announce-ip/d" /data/sentinel/redis-sentinel.conf
  sed -i "/sentinel resolve-hostnames/d" /data/sentinel/redis-sentinel.conf
  sed -i "/sentinel announce-hostnames/d" /data/sentinel/redis-sentinel.conf
  if [ ! -z "$SENTINEL_PASSWORD" ]; then
    sed -i "/sentinel sentinel-user/d" /data/sentinel/redis-sentinel.conf
    sed -i "/sentinel sentinel-pass/d" /data/sentinel/redis-sentinel.conf
  fi
  if [ ! -z "$SENTINEL_SERVICE_PORT" ]; then
    sed -i "/port $SENTINEL_SERVICE_PORT/d" /data/sentinel/redis-sentinel.conf
  else
    sed -i "/port 26379/d" /data/sentinel/redis-sentinel.conf
  fi
fi

if [ ! -z "$SENTINEL_SERVICE_PORT" ]; then
  echo "port $SENTINEL_SERVICE_PORT" >> /data/sentinel/redis-sentinel.conf
else
  echo "port 26379" >> /data/sentinel/redis-sentinel.conf
fi
# shellcheck disable=SC2129
echo "sentinel announce-ip $KB_POD_FQDN" >> /data/sentinel/redis-sentinel.conf
echo "sentinel resolve-hostnames yes" >> /data/sentinel/redis-sentinel.conf
echo "sentinel announce-hostnames yes" >> /data/sentinel/redis-sentinel.conf
if [ ! -z "$SENTINEL_PASSWORD" ]; then
  echo "sentinel sentinel-user $SENTINEL_USER" >> /data/sentinel/redis-sentinel.conf
  echo "sentinel sentinel-pass $SENTINEL_PASSWORD" >> /data/sentinel/redis-sentinel.conf
fi
echo "Starting redis sentinel server..."
exec redis-server /data/sentinel/redis-sentinel.conf --sentinel
echo "Start redis sentinel server succeeded!"