#!/bin/bash
set -euo pipefail

parse_yaml_array() {
    local file="$1"
    [[ -f "$file" ]] && grep "^- " "$file" | sed 's/^- //' | sed 's/^["'\'']//' | sed 's/["'\'']$//'
}

in_array() {
    local target="$1"
    shift
    for item in "$@"; do
        [[ "$item" == "$target" ]] && return 0
    done
    return 1
}

build_json_with_jq() {
    local json="{}"

    for key in "${!patroni_dict[@]}"; do
        json=$(echo "$json" | jq --arg k "$key" --arg v "${patroni_dict[$key]}" '. + {($k): $v}')
    done

    if [[ ${#postgresql_dict[@]} -gt 0 ]]; then
        local pg_params="{}"
        for key in "${!postgresql_dict[@]}"; do
            pg_params=$(echo "$pg_params" | jq --arg k "$key" --arg v "${postgresql_dict[$key]}" '. + {($k): $v}')
        done
        json=$(echo "$json" | jq --argjson params "$pg_params" '. + {postgresql: {parameters: $params}}')
    fi

    echo "$json"
}

BOOTSTRAP_FILE="./restart-parameter.yaml"
PATRONI_PARAMS_FILE="./patroni-parameter.yaml"

mapfile -t restart_params < <(parse_yaml_array "$BOOTSTRAP_FILE")
mapfile -t patroni_params < <(parse_yaml_array "$PATRONI_PARAMS_FILE")

command="reload"
paramName="${1:?missing param name}"
paramValue="${2:?missing value}"
paramValue="${paramValue//\'/}"

declare -A patroni_dict
declare -A postgresql_dict
if in_array "$paramName" "${patroni_params[@]}"; then
    patroni_dict["$paramName"]="$paramValue"
else
    postgresql_dict["$paramName"]="$paramValue"
fi

in_array "$paramName" "${restart_params[@]}" && command="restart"

json_params=$(build_json_with_jq)
curl -s -X PATCH -H "Content-Type: application/json" \
    --data "$json_params" \
    "http://localhost:8008/config"

if [[ "$command" == "restart" ]]; then
    curl -s -X POST "http://localhost:8008/restart"
else
    curl -s -X POST "http://localhost:8008/reload"
fi

