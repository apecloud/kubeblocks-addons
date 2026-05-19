#!/bin/sh
# replication-mode-mapper.sh — alpha.89 v1 commit 12 (Helen 2026-05-20)
# C3 design mapper for the merged replication CmpD.
#
# Purpose
# -------
# Translates the synthetic `replicationMode` ComponentSpec parameter
# ("async" | "semisync") into the four real MariaDB engine variables
# (rpl_semi_sync_master_enabled / rpl_semi_sync_slave_enabled /
# rpl_semi_sync_master_wait_for_slave_count / rpl_semi_sync_master_timeout)
# BEFORE the reconfigureAction's main loop renders any my.cnf or
# runtime-overrides.d/ file. After this mapper runs, the parameter list
# contains only real engine variable assignments; the synthetic key
# `replicationMode` (and its lowercased form `replicationmode`) never
# reaches `SET GLOBAL` and never lands in my.cnf.
#
# Why a mapper instead of a CUE conditional
# ------------------------------------------
# Jack's KB-validator behavioral test (2026-05-20 msg `ea50aa12`)
# proved that KB's `pkg/parameters/validate/cue_util.go
# ValidateConfigWithCue()` validates parameter values against a CUE
# schema but does NOT emit CUE-derived field values back into the
# rendered my.cnf. Expressing C3 precedence in CUE alone would either
# silently ignore `replicationMode` or land the verbatim key in my.cnf
# (which mariadbd rejects as unknown). The C3 design therefore places
# `replicationMode` at the ComponentSpec-parameter layer consumed by
# this addon-side mapper before my.cnf render. commit 11 v2 closed the
# CUE side: `replicationmode?: _|_` forbids the synthetic key from
# landing in my.cnf as a defense-in-depth backstop.
#
# Contract (locked with Jack 2026-05-20 dm:@Jack msg `144afd93` and
# `2e93eb72`)
# ---------------------------------------------------------------
# 1. mapper is the UNIQUE consumer / writer of `replicationMode`.
#    Called exactly once from `mariadb.config.reconfigureAction.persisted`
#    BEFORE the main loop processes any parameter.
# 2. Conflict detection runs BEFORE any file modification. If the
#    user simultaneously supplies `replicationMode` and any of the four
#    real engine variables with disagreeing values, the mapper exits
#    non-zero before touching the parameter list — no partial state.
# 3. On any mapper failure (invalid mode, conflict, IO), the mapper
#    exits non-zero and leaves the parameter list as it was; the main
#    loop never runs, so no `SET GLOBAL` is issued and no
#    runtime-overrides.d/ file is written.
# 4. Only-4-vars path: if `MARIADB_REPLICATION_MODE` is empty or unset,
#    the mapper returns 0 immediately and the parameter list flows
#    through unchanged. The four real engine variables continue to be
#    processed exactly as before.
# 5. Both-consistent path is idempotent: if the user supplied both
#    `replicationMode=semisync` AND the four real variables with the
#    derived values, the mapper does NOT add duplicates; the parameter
#    list ends with one assignment per real variable. Repeated
#    reconfigure with the same input produces identical output.
#
# Defense-in-depth: even though CUE's `replicationmode?: _|_` blocks
# the synthetic key from reaching here, the mapper unconditionally
# strips any `replicationMode` / `replicationmode` line from the
# parameter list as a final safety net before returning.
#
# Source-time interface
# ---------------------
# This script is designed to be SOURCED by the reconfigureAction
# helper or by ShellSpec tests. The sourcing site sets
# `MARIADB_REPLICATION_MODE` from a kbagent-injected env var (the
# ComponentSpec parameter plumbing is wired in a separate commit) and
# calls `apply_replication_mode_mapping <parameter_file>`. Standalone
# invocation is also supported and follows the same contract.
#
# Exit / return codes
# -------------------
#   0 — success (mapper applied derived values or no-op)
#   2 — invalid `MARIADB_REPLICATION_MODE` value (not async / semisync)
#   3 — conflict between `replicationMode` and a user-supplied real var
#   4 — invalid argument (parameter file missing / unreadable)
#   5 — IO failure during atomic rewrite

set -u

REPLICATION_MODE_MAPPER_EXIT_OK=0
REPLICATION_MODE_MAPPER_EXIT_INVALID_MODE=2
REPLICATION_MODE_MAPPER_EXIT_CONFLICT=3
REPLICATION_MODE_MAPPER_EXIT_BAD_ARG=4
REPLICATION_MODE_MAPPER_EXIT_IO=5

# Derive the canonical value for each of the four real engine variables
# given the mode. Stdout is one `name=value` pair per line. Stderr on
# invalid mode. Return non-zero on invalid mode.
#
# Defaults for the two numeric variables (`wait_for_slave_count` and
# `timeout`) match the schema defaults in
# `config/mariadb-config-constraint.cue` so the mapper's "only mode"
# output is consistent with what KB would render from PD defaults if
# the user had instead set the four variables explicitly to those
# values.
replication_mode_derive() {
    mode="$1"
    case "${mode}" in
    async)
        printf "rpl_semi_sync_master_enabled=OFF\n"
        printf "rpl_semi_sync_slave_enabled=OFF\n"
        # wait_for_slave_count and timeout are only meaningful when
        # master_enabled=ON. Per the schema defaults (commit 3 v2),
        # the count default is 1 and the timeout default is 10000ms.
        # The mapper emits them for async too so the override file
        # set is deterministic and a future flip to semisync does
        # not leave stale values from the OFF state.
        printf "rpl_semi_sync_master_wait_for_slave_count=1\n"
        printf "rpl_semi_sync_master_timeout=10000\n"
        ;;
    semisync)
        printf "rpl_semi_sync_master_enabled=ON\n"
        printf "rpl_semi_sync_slave_enabled=ON\n"
        printf "rpl_semi_sync_master_wait_for_slave_count=1\n"
        printf "rpl_semi_sync_master_timeout=10000\n"
        ;;
    *)
        echo "replication-mode-mapper: invalid MARIADB_REPLICATION_MODE='${mode}' (expected async or semisync)" >&2
        return "${REPLICATION_MODE_MAPPER_EXIT_INVALID_MODE}"
        ;;
    esac
}

# Strip any `replicationMode` / `replicationmode` line (any case
# variant; KB's INI parser lowercases keys, so we do the same when
# matching). Reads from $1, writes to stdout.
replication_mode_strip_synthetic() {
    src="$1"
    awk '
        {
            # Normalize the left-hand side to lowercase for comparison
            # without disturbing the value on the right.
            split($0, parts, "=")
            lhs = tolower(parts[1])
            gsub(/[[:space:]]+/, "", lhs)
            if (lhs == "replicationmode") next
            print
        }
    ' "${src}"
}

# Look up a key in a parameter list file (one `name=value` per line).
# Stdout: the value, if present; empty if not. Return 0 always.
replication_mode_lookup() {
    src="$1"
    key="$2"
    awk -v target="${key}" '
        {
            split($0, parts, "=")
            name = parts[1]
            gsub(/[[:space:]]+/, "", name)
            if (tolower(name) == tolower(target)) {
                # Reconstruct the value: everything after the first `=`.
                eq_idx = index($0, "=")
                if (eq_idx > 0) {
                    print substr($0, eq_idx + 1)
                }
                exit
            }
        }
    ' "${src}"
}

# Main entry point. Rewrites the parameter list file atomically in
# place. Returns one of the REPLICATION_MODE_MAPPER_EXIT_* codes.
apply_replication_mode_mapping() {
    param_file="${1:-}"

    if [ -z "${param_file}" ] || [ ! -f "${param_file}" ] || [ ! -r "${param_file}" ]; then
        echo "replication-mode-mapper: parameter file '${param_file}' is missing or unreadable" >&2
        return "${REPLICATION_MODE_MAPPER_EXIT_BAD_ARG}"
    fi

    mode="${MARIADB_REPLICATION_MODE:-}"

    if [ -z "${mode}" ]; then
        # Only-4-vars path: leave the parameter list untouched.
        # Per Jack contract (msg `144afd93`): mapper must return 0 in
        # this case without rewriting the file, so the only-4-vars
        # path is provably not touched.
        return "${REPLICATION_MODE_MAPPER_EXIT_OK}"
    fi

    # Precompute derived values BEFORE any file modification. If the
    # mode is invalid, exit immediately — no partial state.
    derived_file="${param_file}.derived.$$"
    if ! replication_mode_derive "${mode}" > "${derived_file}"; then
        rm -f "${derived_file}" 2>/dev/null || true
        return "${REPLICATION_MODE_MAPPER_EXIT_INVALID_MODE}"
    fi

    # Conflict detection: for each derived var, if the user-supplied
    # parameter list contains a different value for the same key, fail
    # BEFORE any file modification (Jack contract item 2).
    conflict_detected=0
    while IFS='=' read -r derived_name derived_value; do
        [ -n "${derived_name}" ] || continue
        user_value="$(replication_mode_lookup "${param_file}" "${derived_name}")"
        if [ -n "${user_value}" ] && [ "${user_value}" != "${derived_value}" ]; then
            echo "replication-mode-mapper: conflict — replicationMode=${mode} derives ${derived_name}=${derived_value} but parameter list supplies ${derived_name}=${user_value}" >&2
            conflict_detected=1
        fi
    done < "${derived_file}"

    if [ "${conflict_detected}" -ne 0 ]; then
        rm -f "${derived_file}" 2>/dev/null || true
        return "${REPLICATION_MODE_MAPPER_EXIT_CONFLICT}"
    fi

    # Rebuild the parameter list:
    #   1. Strip any synthetic replicationMode / replicationmode line
    #      (defense-in-depth; CUE _|_ should have blocked, but mapper
    #      enforces as the canonical write-site).
    #   2. Keep the user's existing assignments for the four real
    #      engine variables (both-consistent idempotency — no duplicates).
    #   3. Append derived values ONLY for real vars the user did not
    #      already supply.
    rebuild_file="${param_file}.rebuild.$$"
    if ! replication_mode_strip_synthetic "${param_file}" > "${rebuild_file}"; then
        rm -f "${derived_file}" "${rebuild_file}" 2>/dev/null || true
        echo "replication-mode-mapper: failed to strip synthetic key from parameter list" >&2
        return "${REPLICATION_MODE_MAPPER_EXIT_IO}"
    fi

    while IFS='=' read -r derived_name derived_value; do
        [ -n "${derived_name}" ] || continue
        user_value="$(replication_mode_lookup "${rebuild_file}" "${derived_name}")"
        if [ -z "${user_value}" ]; then
            printf "%s=%s\n" "${derived_name}" "${derived_value}" >> "${rebuild_file}" || {
                rm -f "${derived_file}" "${rebuild_file}" 2>/dev/null || true
                echo "replication-mode-mapper: failed to append derived var ${derived_name}" >&2
                return "${REPLICATION_MODE_MAPPER_EXIT_IO}"
            }
        fi
        # When the user-supplied value is present and conflict-free,
        # leave it as-is — idempotent both-consistent path.
    done < "${derived_file}"

    rm -f "${derived_file}" 2>/dev/null || true

    # Atomic in-place rewrite of the parameter list.
    if ! mv "${rebuild_file}" "${param_file}"; then
        rm -f "${rebuild_file}" 2>/dev/null || true
        echo "replication-mode-mapper: failed to atomically rewrite parameter list" >&2
        return "${REPLICATION_MODE_MAPPER_EXIT_IO}"
    fi

    return "${REPLICATION_MODE_MAPPER_EXIT_OK}"
}

# Standalone-invocation entry. When sourced (SHELLSPEC etc.),
# __SOURCED__ is set by the caller and we return without executing.
${__SOURCED__:+false} : || return 0

apply_replication_mode_mapping "$@"
exit $?
