#!/bin/bash

get_mongodb_client_name() {
    if mongosh --version >/dev/null 2>&1; then
        echo mongosh
    else
        echo mongo
    fi
}

mongodb_tls_client_options() {
    if [ "${TLS_ENABLED:-false}" = "true" ]; then
        # Database Tools retain SSL flags independently of the server version.
        case "${1:-mongo}" in
            mongodump|mongorestore)
                echo "--ssl --sslAllowInvalidCertificates --sslAllowInvalidHostnames"
                return
                ;;
        esac
        # The bundled mongo shell follows the server version; mongosh always uses TLS options.
        case "${MONGODB_SERVICE_VERSION:-}:${1:-mongo}" in
            4.0:mongo|4.0.*:mongo)
                echo "--ssl --sslAllowInvalidCertificates --sslAllowInvalidHostnames"
                ;;
            *)
                echo "--tls --tlsAllowInvalidCertificates --tlsAllowInvalidHostnames"
                ;;
        esac
    fi
}

mongodb_tls_uri_options() {
    # PBM and WAL-G use driver URI options, not mongo shell flags.
    if [ "${TLS_ENABLED:-false}" = "true" ]; then
        echo "&tls=true&tlsInsecure=true"
    fi
}

# Shell diagnostics can appear on stdout; only the marked JSON value is a result.
mongodb_query_json() {
    local output result="" line count=0 rc serializer
    serializer='JSON.stringify(kbResult)'
    if [ "$CLIENT" = "mongosh" ]; then
        serializer='EJSON.stringify(kbResult, null, 0, {relaxed: true})'
    fi
    # CLUSTER_MONGO contains the client, connection options and --eval.
    # shellcheck disable=SC2086
    output=$($CLUSTER_MONGO "var kbResult = ($1); print('__KB_MONGODB_RESULT__' + $serializer);") || {
        rc=$?
        printf '%s\n' "$output" >&2
        return "$rc"
    }
    while IFS= read -r line; do
        case "$line" in
            __KB_MONGODB_RESULT__*)
                result=${line#__KB_MONGODB_RESULT__}
                count=$((count + 1))
                ;;
            *) printf '%s\n' "$line" >&2 ;;
        esac
    done <<< "$output"
    if [ "$count" -ne 1 ]; then
        echo "ERROR: Expected one MongoDB query result, got $count." >&2
        return 1
    fi
    printf '%s\n' "$result" | jq -sc 'if length == 1 then .[0] else error("expected one JSON value") end'
}

mongodb_command_json() {
    local result
    result=$(mongodb_query_json "$1") || return $?
    if ! printf '%s\n' "$result" | jq -e '.ok == 1' >/dev/null; then
        echo "ERROR: MongoDB command failed: $result" >&2
        return 1
    fi
    printf '%s\n' "$result"
}
