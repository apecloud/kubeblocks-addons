#!/bin/sh
set -ex

# Based on the Component Definition API, Redis Sentinel deployed independently

echo "start to setup redis sentinel conf"
if [ -f /etc/sentinel/redis-sentinel.conf ]; then
  sed -i "/sentinel announce-ip/d" /etc/sentinel/redis-sentinel.conf
  sed -i "/sentinel resolve-hostnames/d" /etc/sentinel/redis-sentinel.conf
  sed -i "/sentinel announce-hostnames/d" /etc/sentinel/redis-sentinel.conf
  if [ ! -z "$SENTINEL_PASSWORD" ]; then
    sed -i "/sentinel sentinel-user/d" /etc/sentinel/redis-sentinel.conf
    sed -i "/sentinel sentinel-pass/d" /etc/sentinel/redis-sentinel.conf
  fi
fi
# shellcheck disable=SC2129
echo "sentinel announce-ip $KB_POD_FQDN" >> /etc/sentinel/redis-sentinel.conf
echo "sentinel resolve-hostnames yes" >> /etc/sentinel/redis-sentinel.conf
echo "sentinel announce-hostnames yes" >> /etc/sentinel/redis-sentinel.conf
if [ ! -z "$SENTINEL_PASSWORD" ]; then
  echo "sentinel sentinel-user $SENTINEL_USER" >> /etc/sentinel/redis-sentinel.conf
  echo "sentinel sentinel-pass $SENTINEL_PASSWORD" >> /etc/sentinel/redis-sentinel.conf
fi
echo "Starting redis sentinel server..."
exec redis-server /etc/sentinel/redis-sentinel.conf --sentinel
echo "Start redis sentinel server succeeded!"