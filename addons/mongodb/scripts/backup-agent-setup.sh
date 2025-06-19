#!/bin/bash

client_path=$(whereis mongosh | awk '{print $2}')
CLIENT="mongosh"
if [ -z "$client_path" ]; then
    CLIENT="mongo"
fi
# Wait for the local mongodb to be ready
while true; do
    result=$($CLIENT --port $KB_SERVICE_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval "db.adminCommand({ ping: 1 })" 2>/dev/null)
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: Local MongoDB is ready."
        break
    fi
    echo "INFO: Waiting for local MongoDB to be ready..."
    sleep 1
done

# Wait for the mongos process to be ready
while true; do
    result=$($CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval "db.adminCommand({ ping: 1 })" 2>/dev/null)
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: mongos is ready."
        break
    fi
    echo "INFO: Waiting for mongos to be ready..."
    sleep 1
done

exec pbm-agent-entrypoint
