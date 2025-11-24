#!/bin/sh
# wait-index-gateway-ring.sh
# Wait for at least one index gateway instance to be ACTIVE in the ring
# This script is used as an init container for read/write components

set -euo pipefail

BACKEND_SVC="${KB_CLUSTER_NAME}-backend"
BACKEND_PORT="${SERVER_HTTP_PORT:-3100}"
MAX_WAIT="${MAX_WAIT:-300}"  # 5 minutes default
ELAPSED=0

echo "Waiting for index gateway ring to be ready..."
echo "Backend service: ${BACKEND_SVC}.${KB_NAMESPACE}.svc.${CLUSTER_DOMAIN}:${BACKEND_PORT}"
echo "Max wait time: ${MAX_WAIT} seconds"

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Check if backend service is accessible
    if curl -sf "http://${BACKEND_SVC}.${KB_NAMESPACE}.svc.${CLUSTER_DOMAIN}:${BACKEND_PORT}/ready" > /dev/null 2>&1; then
        # Check ring for ACTIVE instances (parse HTML)
        RING_HTML=$(curl -sf "http://${BACKEND_SVC}.${KB_NAMESPACE}.svc.${CLUSTER_DOMAIN}:${BACKEND_PORT}/indexgateway/ring" 2>/dev/null || echo "")
        if [ -n "$RING_HTML" ]; then
            ACTIVE_COUNT=$(echo "$RING_HTML" | grep -o '<td>ACTIVE</td>' | wc -l || echo "0")
            if [ "$ACTIVE_COUNT" -gt "0" ]; then
                echo "Index gateway ring is ready with $ACTIVE_COUNT ACTIVE instance(s)"
                exit 0
            fi
        fi
    fi
    echo "Waiting for index gateway ring... ($ELAPSED/$MAX_WAIT seconds)"
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo "Timeout waiting for index gateway ring after $MAX_WAIT seconds"
exit 1
