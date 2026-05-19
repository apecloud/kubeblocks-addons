#!/bin/sh
# seed-replication-mode-overrides.sh — alpha.89 v1 commit 13 (Helen
# 2026-05-20, Jack post-commit-13-v1 install-time write-site
# requirement msg `696e7b16`).
#
# Translates the install-time `MARIADB_REPLICATION_MODE` Helm value
# (sourced as an env var on the merged CmpD's mariadb container) into
# the four per-parameter override `.cnf` files under
# `runtime-overrides.d/`. mariadbd loads these on first startup via
# `--defaults-extra-file=runtime-overrides.cnf` (which `!includedir`s
# the directory), so the chart-author-selected semisync/async state
# takes effect from the very first mariadbd process — not just after
# the first reconfigureAction runs.
#
# Without this seeder, the env wire from commit 13 v1 was dormant:
# the value sat in the container env but had no consumer until the
# next reconfigureAction triggered the mapper from commit 12. That
# means a chart user setting `mariadb.replication.mode=semisync` at
# install time would still get an async cluster until they did an
# OpsRequest reconfigure — install-time semantics were broken.
#
# The seeder runs at container startup BEFORE the first
# `start_mariadbd_process` call. Its output (the 4 `.cnf` files) is
# byte-identical to what `reconfigureAction.persisted` writes when
# the mapper consumes the same env, so the two write-sites converge
# and a later reconfigure does not flap the values.
#
# Contract
# --------
#
#   1. Source uniqueness preserved: still reads `MARIADB_REPLICATION_MODE`
#      from container env. The Helm-value to env wire (commit 13 v1)
#      is the single source.
#   2. Empty/unset → no-op (return 0). Existing clusters whose Helm
#      values do not set the mode see no behavioral change.
#   3. Conflict not possible at install time (no user-supplied real
#      vars in the path yet); seeder simply writes the 4 derived
#      values.
#   4. Synthetic key never written. Only the four real engine
#      variables land in runtime-overrides.d/.
#   5. Fail-closed on invalid mode: prints sentinel, exits non-zero;
#      caller (CmpD container command) refuses to proceed with
#      mariadbd start.
#   6. Idempotent across restarts: `cmp -s` short-circuit preserves
#      mtime when the override file is already at the target value
#      (so kubelet restarts and pod re-creates don't churn mtime).
#
# Exit codes
# ----------
#
#   0 — success (seeded or no-op)
#   2 — invalid `MARIADB_REPLICATION_MODE` value
#   5 — IO failure during seed

set -u

SEED_REPLICATION_MODE_EXIT_OK=0
SEED_REPLICATION_MODE_EXIT_INVALID_MODE=2
SEED_REPLICATION_MODE_EXIT_IO=5

# Resolve the derived (master_enabled, slave_enabled) pair for a given
# mode. Stdout: two lines `master=<val>` and `slave=<val>`. Stderr +
# non-zero return on invalid mode.
seed_replication_mode_derive_master_slave() {
    mode="$1"
    case "${mode}" in
    async)
        printf "master=OFF\n"
        printf "slave=OFF\n"
        ;;
    semisync)
        printf "master=ON\n"
        printf "slave=ON\n"
        ;;
    *)
        echo "seed-replication-mode-overrides: invalid MARIADB_REPLICATION_MODE='${mode}' (expected async or semisync)" >&2
        return "${SEED_REPLICATION_MODE_EXIT_INVALID_MODE}"
        ;;
    esac
}

# Write a single per-parameter override .cnf file via tmp + atomic
# rename, with byte-equal short-circuit so identical content does not
# refresh mtime. Mirrors the body shape produced by
# `reconfigureAction.persisted` so the two write-sites converge.
seed_replication_mode_write_override() {
    overrides_dir="$1"
    param_name="$2"
    param_value="$3"

    target="${overrides_dir}/${param_name}.cnf"
    tmp="${target}.tmp.$$"

    if ! {
        echo "[mysqld]"
        echo "${param_name} = ${param_value}"
    } > "${tmp}"; then
        rm -f "${tmp}" 2>/dev/null || true
        echo "seed-replication-mode-overrides: failed to write tmp override file for ${param_name}" >&2
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi

    if [ -f "${target}" ] && cmp -s "${tmp}" "${target}"; then
        rm -f "${tmp}" 2>/dev/null || true
        return "${SEED_REPLICATION_MODE_EXIT_OK}"
    fi

    if ! mv "${tmp}" "${target}"; then
        rm -f "${tmp}" 2>/dev/null || true
        echo "seed-replication-mode-overrides: failed to atomically write override file ${target}" >&2
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi

    return "${SEED_REPLICATION_MODE_EXIT_OK}"
}

# Main entry. Reads MARIADB_REPLICATION_MODE from env; returns 0 on
# success (or no-op when env is empty); returns 2 on invalid mode;
# returns 5 on IO failure.
seed_replication_mode_overrides() {
    overrides_dir="${MARIADB_RUNTIME_OVERRIDES_DIR:-/var/lib/mysql/runtime-overrides.d}"
    mode="${MARIADB_REPLICATION_MODE:-}"

    if [ -z "${mode}" ]; then
        # Empty / unset: leave runtime-overrides.d untouched. Preserves
        # existing behavior on clusters whose Helm values do not set
        # mariadb.replication.mode.
        return "${SEED_REPLICATION_MODE_EXIT_OK}"
    fi

    if [ ! -d "${overrides_dir}" ]; then
        echo "seed-replication-mode-overrides: overrides dir ${overrides_dir} does not exist (init-syncer should have created it)" >&2
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi

    # Compute the master/slave values. Fail-closed on invalid mode
    # BEFORE writing anything.
    pair_output="$(seed_replication_mode_derive_master_slave "${mode}")" || return $?
    master_value="$(printf '%s\n' "${pair_output}" | awk -F= '$1=="master"{print $2; exit}')"
    slave_value="$(printf '%s\n' "${pair_output}" | awk -F= '$1=="slave"{print $2; exit}')"

    # Write the four override files in a deterministic order. Each
    # call uses cmp -s to preserve mtime if the on-disk content is
    # already at the target value, so kubelet restarts / pod
    # re-creates do not churn mtime.
    seed_replication_mode_write_override "${overrides_dir}" rpl_semi_sync_master_enabled "${master_value}" || return $?
    seed_replication_mode_write_override "${overrides_dir}" rpl_semi_sync_slave_enabled "${slave_value}" || return $?
    seed_replication_mode_write_override "${overrides_dir}" rpl_semi_sync_master_wait_for_slave_count 1 || return $?
    seed_replication_mode_write_override "${overrides_dir}" rpl_semi_sync_master_timeout 10000 || return $?

    return "${SEED_REPLICATION_MODE_EXIT_OK}"
}

# Standalone-invocation entry. When sourced (ShellSpec etc.),
# __SOURCED__ is set by the caller and we return without executing.
${__SOURCED__:+false} : || return 0

seed_replication_mode_overrides "$@"
exit $?
