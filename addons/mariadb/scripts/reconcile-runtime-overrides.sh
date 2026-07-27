#!/bin/sh
# reconcile-runtime-overrides.sh
#
# Runs at container startup AFTER seed-replication-mode-overrides.sh
# and BEFORE start_mariadbd_process.
#
# When a pod is killed during reconfigureAction (e.g. chaos kill
# mid-reconfigure), the override file in runtime-overrides.d/ may
# retain a stale value from a previous reconfigure while the
# controller has already updated the ConfigMap to the new value.
# Because mariadbd loads --defaults-extra-file (overrides) AFTER the
# ConfigMap-mounted config at /etc/mysql/conf.d/, stale overrides
# take precedence and the pod starts with the wrong parameter value.
#
# This script reconciles: for each override file whose parameter also
# appears in the ConfigMap, it updates the override to match the
# ConfigMap value (the controller's source of truth).
#
# Contract
# --------
#
#   1. ConfigMap is source of truth. KB controller always updates the
#      ConfigMap before invoking reconfigureAction; the ConfigMap
#      reflects the controller's intended parameter state.
#   2. Override files for parameters NOT in ConfigMap are left alone.
#      These may come from seed-replication-mode-overrides.sh or other
#      non-ConfigMap sources.
#   3. Matching values are a no-op: mtime is preserved via cmp -s.
#   4. Atomic temp+mv for updates (same pattern as reconfigureAction).
#   5. Best-effort: a single file failure logs a warning and continues
#      to the next file. The script returns 0 unless the overrides dir
#      is missing (unexpected) — the caller should fail closed.
#   6. Idempotent across restarts.
#
# Exit codes
# ----------
#
#   0 — success (reconciled, no-op, or no files to reconcile)
#   1 — overrides dir missing (unexpected; init-syncer should create)

set -u

RECONCILE_OVERRIDES_DIR="${MARIADB_RUNTIME_OVERRIDES_DIR:-/var/lib/mysql/runtime-overrides.d}"
RECONCILE_CONFIGMAP_PATH="${MARIADB_CONFIGMAP_PATH:-/etc/mysql/conf.d/my.cnf}"

# Parse a parameter's value from a my.cnf-format file.
# Returns the LAST occurrence in the [mysqld] section (MariaDB
# last-value-wins semantics). Prints empty string if not found.
reconcile_parse_configmap_value() {
    param="$1"
    config="$2"

    awk -v param="$param" '
        /^[[:space:]]*\[mysqld\]/ { in_mysqld=1; next }
        /^[[:space:]]*\[/         { in_mysqld=0; next }
        !in_mysqld                { next }
        /^[[:space:]]*#/          { next }
        /^[[:space:]]*;/          { next }
        /^[[:space:]]*$/          { next }
        {
            idx = index($0, "=")
            if (idx == 0) next
            key = substr($0, 1, idx - 1)
            val = substr($0, idx + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            gsub(/-/, "_", key)
            if (key == param) last = val
        }
        END { if (last != "") print last }
    ' "$config"
}

# Parse the value from a single-parameter override file.
reconcile_parse_override_value() {
    override="$1"

    awk '
        /^[[:space:]]*#/  { next }
        /^[[:space:]]*;/  { next }
        /^[[:space:]]*$/  { next }
        /^[[:space:]]*\[/ { next }
        {
            idx = index($0, "=")
            if (idx == 0) next
            val = substr($0, idx + 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
            print val
            exit
        }
    ' "$override"
}

reconcile_runtime_overrides() {
    overrides_dir="${RECONCILE_OVERRIDES_DIR}"
    configmap="${RECONCILE_CONFIGMAP_PATH}"

    if [ ! -d "${overrides_dir}" ]; then
        echo "reconcile-runtime-overrides: overrides dir ${overrides_dir} missing" >&2
        return 1
    fi

    if [ ! -f "${configmap}" ]; then
        return 0
    fi

    reconciled=0
    skipped=0

    for override_file in "${overrides_dir}"/*.cnf; do
        [ -f "${override_file}" ] || continue

        filename="$(basename "${override_file}")"
        param_name="${filename%.cnf}"

        case "${param_name}" in
            *.tmp.*) continue ;;
        esac

        cm_value="$(reconcile_parse_configmap_value "${param_name}" "${configmap}")"

        if [ -z "${cm_value}" ]; then
            skipped=$((skipped + 1))
            continue
        fi

        override_value="$(reconcile_parse_override_value "${override_file}")"

        if [ "${cm_value}" = "${override_value}" ]; then
            continue
        fi

        tmp="${override_file}.tmp.$$"
        if ! printf '[mysqld]\n%s = %s\n' "${param_name}" "${cm_value}" > "${tmp}" 2>/dev/null; then
            rm -f "${tmp}" 2>/dev/null || true
            echo "reconcile-runtime-overrides: failed to write tmp for ${param_name}" >&2
            continue
        fi

        if [ -f "${override_file}" ] && cmp -s "${tmp}" "${override_file}"; then
            rm -f "${tmp}" 2>/dev/null || true
            continue
        fi

        if ! mv "${tmp}" "${override_file}"; then
            rm -f "${tmp}" 2>/dev/null || true
            echo "reconcile-runtime-overrides: failed to rename tmp for ${param_name}" >&2
            continue
        fi

        echo "reconcile-runtime-overrides: ${param_name} override '${override_value}' -> '${cm_value}' (ConfigMap source of truth)"
        reconciled=$((reconciled + 1))
    done

    if [ "${reconciled}" -gt 0 ]; then
        echo "reconcile-runtime-overrides: reconciled ${reconciled} override(s), ${skipped} not in ConfigMap (left alone)"
    fi

    return 0
}

# Standalone-invocation entry. When sourced (ShellSpec etc.),
# __SOURCED__ is set by the caller and we return without executing.
${__SOURCED__:+false} : || return 0

reconcile_runtime_overrides "$@"
exit $?
