#!/bin/sh
set -eu

parse_yaml_array() {
    file="$1"
    [ -f "$file" ] && grep "^- " "$file" | sed 's/^- //' | sed 's/^["'\'']//' | sed 's/["'\'']$//'
}

in_array() {
    target="$1"
    shift
    items="$*"

    for item in $items; do
        [ "$item" = "$target" ] && return 0
    done
    return 1
}

# Call the local patroni REST API and propagate failures: a connection error or
# a non-2xx response must fail the reconfigure action instead of reporting
# success while the parameter change was never applied.
patroni_api() {
    method="$1"
    endpoint="$2"
    shift 2

    if ! response=$(curl -s -m 30 -w "\n%{http_code}" -X "$method" "$@" "http://localhost:8008${endpoint}"); then
        echo "ERROR: cannot reach patroni API: ${method} ${endpoint}" >&2
        return 1
    fi
    http_code=$(printf '%s\n' "$response" | tail -n 1)
    body=$(printf '%s\n' "$response" | sed '$d')
    [ -n "$body" ] && echo "patroni ${method} ${endpoint} response: ${body}"
    case "$http_code" in
        2*) return 0 ;;
        *)
            echo "ERROR: patroni API ${method} ${endpoint} failed with HTTP ${http_code}: ${body}" >&2
            return 1
            ;;
    esac
}

update_parameter() {
    SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
    BOOTSTRAP_FILE="${SCRIPT_DIR}/restart-parameter.yaml"
    PATRONI_PARAMS_FILE="${SCRIPT_DIR}/patroni-parameter.yaml"

    restart_params=$(parse_yaml_array "$BOOTSTRAP_FILE")
    patroni_params=$(parse_yaml_array "$PATRONI_PARAMS_FILE")

    command="reload"
    paramName="${1:?missing param name}"
    paramValue="${2:?missing value}"
    paramValue=$(echo "$paramValue" | sed "s/'//g")

    json_params="{}"
    if in_array "$paramName" "$patroni_params"; then
        json_params=$(echo "$json_params" | jq --arg k "$paramName" --arg v "$paramValue" '. + {($k): $v}')
    else
        pg_params=$(echo "{}" | jq --arg k "$paramName" --arg v "$paramValue" '. + {($k): $v}')
        json_params=$(echo "$json_params" | jq --argjson params "$pg_params" '. + {postgresql: {parameters: $params}}')
    fi

    in_array "$paramName" "$restart_params" && command="restart"

    patroni_api PATCH /config -H "Content-Type: application/json" --data "$json_params"

    if [ "$command" = "restart" ]; then
        patroni_api POST /restart
    else
        patroni_api POST /reload
    fi
}

# if test by shell spec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

update_parameter "$@"
