#!/bin/sh
set -e

DATA_DIR="${RABBITMQ_DATA_DIR:-/var/lib/rabbitmq}"

if [ ! -f "$DATA_DIR/enabled_plugins" ]; then
  cp /etc/rabbitmq/enabled_plugins "$DATA_DIR/enabled_plugins"
fi

cp /root/erlang.cookie "$DATA_DIR/.erlang.cookie"
chown rabbitmq:rabbitmq "$DATA_DIR/.erlang.cookie"
chmod 400 "$DATA_DIR/.erlang.cookie"

cat > /etc/rabbitmq/conf.d/10-kubeblocks-default-user.conf <<EOF
default_user = ${RABBITMQ_DEFAULT_USER}
default_pass = ${RABBITMQ_DEFAULT_PASS}
EOF

exec /opt/rabbitmq/sbin/rabbitmq-server
