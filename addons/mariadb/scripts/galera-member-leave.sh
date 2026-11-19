#!/bin/sh

# Compatibility no-op for ComponentDefinitions published before alpha.27.
#
# Galera removes a departed member through its native membership protocol and
# the mariadb container preStop owns graceful shutdown. Keep this stable script
# path available for existing alpha.26 consumers without issuing SQL or
# mutating wsrep state from the kbagent execution container.

echo "galera memberLeave compatibility no-op: native membership handles eviction"
exit 0
