#!/bin/sh
# check-index-gateway-ring.sh
# Check if index gateway ring has ACTIVE instances
# This script is used in startupProbe and readinessProbe
# Uses curl from tools volume (copied by initContainer)

LOCAL_PORT="${SERVER_HTTP_PORT:-3100}"
CURL="/kb-tools/curl"

# Check if curl is available
if [ ! -x "$CURL" ]; then
    echo "curl not found at $CURL"
    exit 1
fi

# Check if Loki service is ready
if ! "$CURL" -sf "http://localhost:${LOCAL_PORT}/ready" > /dev/null 2>&1; then
    echo "Loki service not ready"
    exit 1
fi

# Check index gateway ring for ACTIVE instances
RING_HTML=$("$CURL" -sf "http://localhost:${LOCAL_PORT}/indexgateway/ring" 2>/dev/null || echo "")
if [ -z "$RING_HTML" ]; then
    echo "Cannot access index gateway ring endpoint"
    exit 1
fi

# Check HTML for ACTIVE status instances
ACTIVE_COUNT=$(echo "$RING_HTML" | grep -o '<td>ACTIVE</td>' | wc -l || echo "0")
if [ "$ACTIVE_COUNT" -eq "0" ]; then
    echo "Index gateway ring is empty, no ACTIVE instances found"
    exit 1
fi

echo "Index gateway ring is ready with $ACTIVE_COUNT ACTIVE instance(s)"
exit 0
