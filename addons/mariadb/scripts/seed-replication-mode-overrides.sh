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

# Helper: write a single tmp file for the (name, value) pair into
# overrides_dir. Returns rc=5 on write failure (tmp cleaned up).
# Tmp filename pattern: `<param_name>.cnf.tmp.<pid>` colocated with
# the eventual target so the later mv is intra-filesystem atomic.
#
# Implementation note (Jack B5 smoke msg `6e6eab69`): uses a single
# `printf ... > tmp` simple command rather than `{ ... } > tmp`
# because bash compound-command redirection failures do NOT propagate
# to the surrounding `if !` test (see `bash -c 'if ! { echo ok; } >
# /no-such-dir/file; then echo X; fi'` — X never prints even though
# the redirect failed). A simple command's redirect failure does
# propagate, so we use printf and additionally post-check `[ -s ]`
# as a belt-and-suspenders guard against truncated writes.
seed_replication_mode_write_one_tmp() {
    overrides_dir="$1"
    param_name="$2"
    param_value="$3"

    target="${overrides_dir}/${param_name}.cnf"
    tmp="${target}.tmp.$$"

    if ! printf '[mysqld]\n%s = %s\n' "${param_name}" "${param_value}" > "${tmp}" 2>/dev/null; then
        rm -f "${tmp}" 2>/dev/null || true
        echo "seed-replication-mode-overrides: failed to write tmp override file for ${param_name}" >&2
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi
    if [ ! -s "${tmp}" ]; then
        rm -f "${tmp}" 2>/dev/null || true
        echo "seed-replication-mode-overrides: tmp override file for ${param_name} is empty after write (write was silently truncated)" >&2
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi
    return "${SEED_REPLICATION_MODE_EXIT_OK}"
}

# Helper: cleanup all 3 tmp files (used on any failure in the
# write-all-then-commit path). commit 16 dropped
# rpl_semi_sync_master_wait_for_slave_count (MariaDB unsupported).
seed_replication_mode_cleanup_all_tmps() {
    overrides_dir="$1"
    for name in rpl_semi_sync_master_enabled rpl_semi_sync_slave_enabled rpl_semi_sync_master_timeout; do
        rm -f "${overrides_dir}/${name}.cnf.tmp.$$" 2>/dev/null || true
    done
}

# Helper: verify that an existing target path is absent OR a regular
# file. If it exists but is a directory / symlink-to-dir / device /
# fifo / socket, refuse to write because `mv tmp target` would
# silently move tmp INTO a directory and leave the target unchanged
# in shape (Jack B4 fix msg `6e6eab69`).
seed_replication_mode_validate_target_type() {
    target="$1"
    if [ -e "${target}" ] && [ ! -f "${target}" ]; then
        echo "seed-replication-mode-overrides: target ${target} exists but is not a regular file (refusing to write — would not produce the expected override)" >&2
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi
    return "${SEED_REPLICATION_MODE_EXIT_OK}"
}

# Main entry. Reads MARIADB_REPLICATION_MODE from env; returns 0 on
# success (or no-op when env is empty); returns 2 on invalid mode;
# returns 5 on IO failure.
#
# Multi-file commit pattern (Jack B5 fix msg `6e6eab69`): writes
# happen in 5 phases so a failure in any single file leaves the
# overrides dir in its prior state rather than partial / mixed.
#
#   Phase A — derive: compute all 4 (name, value) pairs into shell
#             vars. Fail-closed on invalid mode BEFORE any disk write.
#   Phase B — pre-validate target types: check each target is absent
#             OR a regular file (B4 backstop). Fail-closed without
#             touching disk.
#   Phase C — write 4 tmp files. If any tmp write fails, clean up all
#             4 tmp files (any subset that exists) and return rc=5.
#             At this point no target has been renamed yet, so the
#             on-disk overrides dir is unchanged from the prior run.
#   Phase D — byte-equal compare each tmp to its target; build the
#             rename list. Targets that are already byte-identical to
#             the staged content are skipped to preserve mtime.
#   Phase E — rename each entry in the rename list. Each rename is
#             intra-filesystem and atomic; the renames happen in tight
#             sequence to minimize the partial-commit window. If any
#             rename fails, the remaining tmp files are cleaned up
#             and rc=5 is returned (best-effort partial-state
#             reporting; previously-renamed targets are NOT rolled
#             back, but the failure exits the action loudly and the
#             container refuses to start mariadbd).
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

    # --- Phase A: derive ---
    pair_output="$(seed_replication_mode_derive_master_slave "${mode}")" || return $?
    master_value="$(printf '%s\n' "${pair_output}" | awk -F= '$1=="master"{print $2; exit}')"
    slave_value="$(printf '%s\n' "${pair_output}" | awk -F= '$1=="slave"{print $2; exit}')"

    # --- Phase B: pre-validate target types (B4) ---
    # alpha.89 v1 commit 16 (Helen 2026-05-20, live N=1 third
    # first-blocker fix): the previous 4-var list included the
    # MySQL-specific `rpl_semi_sync_master_wait_for_slave_count`
    # which MariaDB 11.4 does not recognize. Setting it in
    # runtime-overrides.d/ causes mariadbd to exit on first
    # startup with rc=7 "unknown variable". Removed. MariaDB
    # semisync waits for one slave; there is no equivalent
    # MariaDB variable.
    for name in rpl_semi_sync_master_enabled rpl_semi_sync_slave_enabled rpl_semi_sync_master_timeout; do
        if ! seed_replication_mode_validate_target_type "${overrides_dir}/${name}.cnf"; then
            return "${SEED_REPLICATION_MODE_EXIT_IO}"
        fi
    done

    # --- Phase C: write the 3 tmp files (commit 16 dropped
    # rpl_semi_sync_master_wait_for_slave_count, MariaDB-unsupported) ---
    if ! seed_replication_mode_write_one_tmp "${overrides_dir}" rpl_semi_sync_master_enabled "${master_value}"; then
        seed_replication_mode_cleanup_all_tmps "${overrides_dir}"
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi
    if ! seed_replication_mode_write_one_tmp "${overrides_dir}" rpl_semi_sync_slave_enabled "${slave_value}"; then
        seed_replication_mode_cleanup_all_tmps "${overrides_dir}"
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi
    if ! seed_replication_mode_write_one_tmp "${overrides_dir}" rpl_semi_sync_master_timeout 10000; then
        seed_replication_mode_cleanup_all_tmps "${overrides_dir}"
        return "${SEED_REPLICATION_MODE_EXIT_IO}"
    fi

    # --- Phase D & E: byte-equal compare + rename ---
    for name in rpl_semi_sync_master_enabled rpl_semi_sync_slave_enabled rpl_semi_sync_master_timeout; do
        target="${overrides_dir}/${name}.cnf"
        tmp="${target}.tmp.$$"
        if [ -f "${target}" ] && cmp -s "${tmp}" "${target}"; then
            # Already at target value — skip rename to preserve mtime.
            rm -f "${tmp}" 2>/dev/null || true
            continue
        fi
        if ! mv "${tmp}" "${target}"; then
            seed_replication_mode_cleanup_all_tmps "${overrides_dir}"
            echo "seed-replication-mode-overrides: failed to atomically rename tmp into place at ${target}; some prior renames in this batch may have already committed" >&2
            return "${SEED_REPLICATION_MODE_EXIT_IO}"
        fi
        # Post-rename sanity: target must now be a regular file. If
        # the rename succeeded into a directory shape we never want
        # to silently advertise success.
        if [ ! -f "${target}" ]; then
            seed_replication_mode_cleanup_all_tmps "${overrides_dir}"
            echo "seed-replication-mode-overrides: post-rename target ${target} is not a regular file (rename did not produce the expected override)" >&2
            return "${SEED_REPLICATION_MODE_EXIT_IO}"
        fi
    done

    return "${SEED_REPLICATION_MODE_EXIT_OK}"
}

# Standalone-invocation entry. When sourced (ShellSpec etc.),
# __SOURCED__ is set by the caller and we return without executing.
${__SOURCED__:+false} : || return 0

seed_replication_mode_overrides "$@"
exit $?
