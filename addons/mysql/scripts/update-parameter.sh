#!/bin/bash

mysql_exec() {
    local query="$1"
    mysql --user="${MYSQL_ADMIN_USER}" --password="${MYSQL_ADMIN_PASSWORD}" \
        --host=127.0.0.1 -P 3306 -NBe "${query}"
}

normalize_parameter_name() {
    local name="$1"
    name="${name#loose_}"
    printf '%s' "${name//-/_}"
}

normalize_parameter_value() {
    local value="$1"
    local number

    if [[ "$value" =~ ^[0-9]+$ ]]; then
        printf '%s' "$value"
    elif [[ "$value" =~ ^([0-9]+)(K|KB|k|kb)$ ]]; then
        number="${BASH_REMATCH[1]}"
        printf '%s' "$((number * 1024))"
    elif [[ "$value" =~ ^([0-9]+)(M|MB|m|mb)$ ]]; then
        number="${BASH_REMATCH[1]}"
        printf '%s' "$((number * 1024 * 1024))"
    elif [[ "$value" =~ ^([0-9]+)(G|GB|g|gb)$ ]]; then
        number="${BASH_REMATCH[1]}"
        printf '%s' "$((number * 1024 * 1024 * 1024))"
    else
        printf '%s' "$value"
    fi
}

sql_string_literal() {
    local hex

    if ! hex=$(
        set -o pipefail
        printf '%s' "$1" | od -An -v -tx1 | tr -d ' \n'
    ); then
        return 1
    fi
    printf "X'%s'" "$hex"
}

apply_parameter() {
    local name value normalized_value sql_literal query result
    name=$(normalize_parameter_name "$1")
    value="$2"

    if [[ ! "$name" =~ ^[A-Za-z0-9_]+$ ]]; then
        printf 'Invalid parameter name: %s\n' "$name" >&2
        return 1
    fi

    normalized_value=$(normalize_parameter_value "$value")
    if [[ "$normalized_value" =~ ^[0-9]+$ ]]; then
        query="SET GLOBAL ${name} = ${normalized_value};"
    else
        if ! sql_literal=$(sql_string_literal "$normalized_value"); then
            printf 'Failed to encode parameter %s as a SQL string literal\n' "$name" >&2
            return 1
        fi
        query="SET GLOBAL ${name} = ${sql_literal};"
    fi

    if ! result=$(mysql_exec "$query" 2>&1); then
        printf 'Failed to set parameter %s to value %s: %s\n' "$name" "$value" "$result" >&2
        return 1
    fi
    printf 'Set parameter %s to value %s\n' "$name" "$value"
}

read_desired_value() {
    local parameter="$1"
    local config_file="$2"

    awk -v wanted="$parameter" '
        function trim(value) {
            sub(/^[[:space:]]+/, "", value)
            sub(/[[:space:]]+$/, "", value)
            return value
        }
        /^[[:space:]]*\[/ {
            section = tolower($0)
            gsub(/[[:space:]]/, "", section)
            next
        }
        section != "[mysqld]" || /^[[:space:]]*[#;]/ { next }
        {
            separator = index($0, "=")
            if (separator == 0) {
                next
            }
            name = tolower(trim(substr($0, 1, separator - 1)))
            gsub(/-/, "_", name)
            sub(/^loose_/, "", name)
            if (name == wanted) {
                value = trim(substr($0, separator + 1))
                sub(/[[:space:]]+[;#].*$/, "", value)
                found = 1
            }
        }
        END {
            if (!found) {
                exit 1
            }
            print value
        }
    ' "$config_file"
}

unquote_config_value() {
    local value="$1"
    if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '%s' "$value"
    fi
}

resolve_dynamic_parameters_file() {
    local server_version

    if [ -n "${MYSQL_DYNAMIC_PARAMETERS_FILE:-}" ]; then
        printf '%s' "$MYSQL_DYNAMIC_PARAMETERS_FILE"
        return
    fi

    if ! server_version=$(mysql_exec "SELECT VERSION();" 2>/dev/null); then
        printf 'Could not determine MySQL version for rendered-config fallback; next-retry-safe: yes\n' >&2
        return 1
    fi

    case "$server_version" in
        5.7.*)
            printf '%s' /scripts/mysql5.7-dynamic-parameters.txt
            ;;
        8.*)
            printf '%s' /scripts/mysql8-dynamic-parameters.txt
            ;;
        *)
            printf 'Unsupported MySQL version for rendered-config fallback: %s; next-retry-safe: yes\n' \
                "$server_version" >&2
            return 1
            ;;
    esac
}

lookup_live_value() {
    local parameter="$1"
    local live_file="$2"

    awk -F '\t' -v wanted="$parameter" '
        tolower($1) == tolower(wanted) {
            print $2
            found = 1
            exit
        }
        END { if (!found) exit 1 }
    ' "$live_file"
}

values_equal() {
    local desired actual
    desired=$(normalize_parameter_value "$1")
    actual=$(normalize_parameter_value "$2")

    [ "$desired" = "$actual" ] ||
        [ "$(printf '%s' "$desired" | tr '[:upper:]' '[:lower:]')" = \
          "$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')" ]
}

rendered_config_fingerprint() {
    cksum "$1" "$2" | cksum | awk '{ print $1 ":" $2 }'
}

persist_reconfigure_receipt() {
    local receipt_file="$1"
    local state="$2"
    local fingerprint="$3"
    local temporary="${receipt_file}.$$"

    if ! printf '%s:%s\n' "$state" "$fingerprint" >"$temporary" ||
        ! mv -f "$temporary" "$receipt_file"; then
        rm -f "$temporary"
        return 1
    fi
}

apply_rendered_dynamic_differences() {
    local config_file="${MYSQL_CONFIG_FILE:-/etc/mysql/conf.d/my.cnf}"
    local receipt_file="${MYSQL_RECONFIGURE_RECEIPT_FILE:-/tmp/kubeblocks-mysql-reconfigure.receipt}"
    local allowlist_file live_file parameter normalized_name desired actual verified fingerprint
    local applied=0 configured=0

    if ! allowlist_file=$(resolve_dynamic_parameters_file); then
        return 1
    fi
    if [ ! -r "$config_file" ] || [ ! -r "$allowlist_file" ]; then
        printf 'Rendered-config fallback inputs are unreadable; runtime arguments are missing; next-retry-safe: yes\n' >&2
        return 1
    fi
    if ! fingerprint=$(rendered_config_fingerprint "$config_file" "$allowlist_file"); then
        printf 'Could not fingerprint rendered-config fallback inputs; next-retry-safe: yes\n' >&2
        return 1
    fi

    live_file=$(mktemp)
    if ! mysql_exec "SHOW GLOBAL VARIABLES" >"$live_file"; then
        rm -f "$live_file"
        printf 'Could not read live MySQL variables; runtime arguments are missing; next-retry-safe: yes\n' >&2
        return 1
    fi

    # Validate the complete rendered/live observation set before mutating any
    # variable. A completion receipt must never certify partial visibility.
    while IFS= read -r parameter || [ -n "$parameter" ]; do
        [ -n "$parameter" ] || continue
        normalized_name=$(normalize_parameter_name "$parameter")
        if ! desired=$(read_desired_value "$normalized_name" "$config_file"); then
            continue
        fi
        configured=$((configured + 1))
        if ! lookup_live_value "$normalized_name" "$live_file" >/dev/null; then
            rm -f "$live_file"
            printf 'Configured dynamic parameter %s is absent from live MySQL variables; next-retry-safe: yes\n' \
                "$normalized_name" >&2
            return 1
        fi
    done <"$allowlist_file"
    if [ "$configured" -eq 0 ]; then
        rm -f "$live_file"
        printf 'No rendered allowlisted dynamic parameter was observable; runtime arguments are missing; next-retry-safe: yes\n' >&2
        return 1
    fi

    while IFS= read -r parameter || [ -n "$parameter" ]; do
        [ -n "$parameter" ] || continue
        normalized_name=$(normalize_parameter_name "$parameter")
        if ! desired=$(read_desired_value "$normalized_name" "$config_file"); then
            continue
        fi
        desired=$(unquote_config_value "$desired")
        actual=$(lookup_live_value "$normalized_name" "$live_file")
        if values_equal "$desired" "$actual"; then
            continue
        fi
        if [ "$applied" -eq 0 ] &&
            ! persist_reconfigure_receipt "$receipt_file" pending "$fingerprint"; then
            rm -f "$live_file"
            printf 'Could not persist the rendered-config pending receipt; next-retry-safe: yes\n' >&2
            return 1
        fi
        if ! apply_parameter "$normalized_name" "$desired"; then
            rm -f "$live_file"
            return 1
        fi
        if ! verified=$(mysql_exec "SHOW GLOBAL VARIABLES WHERE Variable_name = '${normalized_name}'" 2>/dev/null); then
            rm -f "$live_file"
            printf 'Could not verify parameter %s after update; next-retry-safe: yes\n' \
                "$normalized_name" >&2
            return 1
        fi
        verified="${verified#*$'\t'}"
        if ! values_equal "$desired" "$verified"; then
            rm -f "$live_file"
            printf 'Parameter %s did not converge to the rendered value; next-retry-safe: yes\n' \
                "$normalized_name" >&2
            return 1
        fi
        applied=$((applied + 1))
    done <"$allowlist_file"
    rm -f "$live_file"

    if [ "$applied" -eq 0 ]; then
        if [ -r "$receipt_file" ] &&
            { [ "$(cat "$receipt_file")" = "pending:${fingerprint}" ] ||
              [ "$(cat "$receipt_file")" = "complete:${fingerprint}" ]; }; then
            if ! persist_reconfigure_receipt "$receipt_file" complete "$fingerprint"; then
                printf 'Could not finalize the rendered-config completion receipt; next-retry-safe: yes\n' >&2
                return 1
            fi
            printf 'Rendered dynamic parameters already converged for the recorded config\n'
            return 0
        fi
        printf 'No rendered dynamic difference was observable while runtime arguments are missing; next-retry-safe: yes\n' >&2
        return 1
    fi
    if ! persist_reconfigure_receipt "$receipt_file" complete "$fingerprint"; then
        printf 'Could not persist the rendered-config completion receipt; next-retry-safe: yes\n' >&2
        return 1
    fi
    printf 'Applied %s rendered dynamic parameter(s)\n' "$applied"
}

main() {
    case "$#" in
        0)
            apply_rendered_dynamic_differences
            ;;
        1)
            printf 'Missing parameter value for %s; next-retry-safe: yes\n' "$1" >&2
            return 1
            ;;
        2)
            apply_parameter "$1" "$2"
            ;;
        *)
            printf 'Expected exactly two runtime arguments, got %s; next-retry-safe: yes\n' "$#" >&2
            return 1
            ;;
    esac
}

main "$@"
