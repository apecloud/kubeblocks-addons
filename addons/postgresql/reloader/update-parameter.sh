#!/bin/ash
set -euo pipefail

parse_yaml_array() {
    local file="$1"
    [[ -f "$file" ]] && grep "^- " "$file" | sed 's/^- //' | sed 's/^["'\'']//' | sed 's/["'\'']$//'
}

in_array() {
    local target="$1"
    shift
    items="$*"

    for item in $items; do
        [ "$item" = "$target" ] && return 0
    done
    return 1
}

BOOTSTRAP_FILE="./restart-parameter.yaml"
PATRONI_PARAMS_FILE="./patroni-parameter.yaml"

restart_params=$(parse_yaml_array "$BOOTSTRAP_FILE")
patroni_params=$(parse_yaml_array "$PATRONI_PARAMS_FILE")

command="reload"
paramName="${1:?missing param name}"
paramValue="${2:?missing value}"
paramValue="${paramValue//\'/}"

if in_array "$paramName" "$patroni_params"; then
    json_params=$(echo "$json_params" | jq --arg k "$paramName" --arg v "$paramValue" '. + {($k): $v}')
else
    pg_params=$(echo "{}" | jq --arg k "$paramName" --arg v "$paramValue" '. + {($k): $v}')
    json_params=$(echo "$json_params" | jq --argjson params "$pg_params" '. + {postgresql: {parameters: $params}}')
fi

in_array "$paramName" "$restart_params" && command="restart"

curl -s -X PATCH -H "Content-Type: application/json" \
    --data "$json_params" \
    "http://localhost:8008/config"

if [[ "$command" == "restart" ]]; then
    curl -s -X POST "http://localhost:8008/restart"
else
    curl -s -X POST "http://localhost:8008/reload"
fi

