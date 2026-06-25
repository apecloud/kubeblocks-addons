# shellcheck shell=sh

# alpha.89 v1 commit 13 v2 (Helen 2026-05-20, Jack
# post-commit-13-v1 install-time write-site requirement msg
# `696e7b16`) — behavioral lock on
# scripts/seed-replication-mode-overrides.sh, the install-time
# seeder that translates `MARIADB_REPLICATION_MODE` (Helm value
# `mariadb.replication.mode` → CmpD container env) into the four
# per-parameter override `.cnf` files BEFORE the first mariadbd
# process starts.
#
# Strategy: source the script with __SOURCED__=1 and invoke
# seed_replication_mode_overrides against a tmp overrides dir.
# Assert exit code, file contents, and mtime behavior.

Describe "alpha.89 commit 13 v2 seed-replication-mode-overrides.sh"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mariadb/scripts/seed-replication-mode-overrides.sh" "$(repo_root)"
  }

  setup() {
    tmpdir=$(mktemp -d -t mariadb-seed-XXXXXX)
    overrides_dir="${tmpdir}/overrides"
    mkdir -p "${overrides_dir}"
    MARIADB_RUNTIME_OVERRIDES_DIR="${overrides_dir}"
    export MARIADB_RUNTIME_OVERRIDES_DIR
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  run_seeder() {
    # shellcheck disable=SC1090
    __SOURCED__=1 . "$(script_path)"
    seed_replication_mode_overrides
  }

  Describe "empty env (no-op)"
    It "returns 0 and does not create override files when MARIADB_REPLICATION_MODE is unset"
      unset MARIADB_REPLICATION_MODE
      run_seeder
      rc=$?
      file_count=$(ls "${overrides_dir}" 2>/dev/null | wc -l | tr -d ' ')
      When call test "${rc}" -eq 0 -a "${file_count}" -eq 0
      The status should be success
    End

    It "returns 0 and does not create override files when MARIADB_REPLICATION_MODE is empty string"
      MARIADB_REPLICATION_MODE=""
      export MARIADB_REPLICATION_MODE
      run_seeder
      rc=$?
      file_count=$(ls "${overrides_dir}" 2>/dev/null | wc -l | tr -d ' ')
      When call test "${rc}" -eq 0 -a "${file_count}" -eq 0
      The status should be success
    End
  End

  Describe "semisync seeds the four engine variables"
    It "writes rpl_semi_sync_master_enabled=ON"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_master_enabled.cnf" should include "[mysqld]"
      The contents of file "${overrides_dir}/rpl_semi_sync_master_enabled.cnf" should include "rpl_semi_sync_master_enabled = ON"
    End

    It "writes rpl_semi_sync_slave_enabled=ON"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_slave_enabled.cnf" should include "rpl_semi_sync_slave_enabled = ON"
    End

    It "does NOT write rpl_semi_sync_master_wait_for_slave_count.cnf (commit 16 MariaDB-unsupported drop)"
      # alpha.89 v1 commit 16 (Helen 2026-05-20, live N=1 third
      # first-blocker fix): MariaDB 11.4 does NOT support this
      # MySQL-specific variable. Writing it to runtime-overrides.d/
      # causes mariadbd to exit on first startup with rc=7 unknown
      # variable, CrashLooping the engine container.
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      run_seeder
      file_exists=$([ -e "${overrides_dir}/rpl_semi_sync_master_wait_for_slave_count.cnf" ] && echo "exists" || echo "absent")
      When call test "${file_exists}" = "absent"
      The status should be success
    End

    It "writes rpl_semi_sync_master_timeout=10000 when no timeout override exists"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_master_timeout.cnf" should include "rpl_semi_sync_master_timeout = 10000"
    End

    It "preserves an existing valid rpl_semi_sync_master_timeout override across restart seeding"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      printf '[mysqld]\nrpl_semi_sync_master_timeout = 3000\n' > "${overrides_dir}/rpl_semi_sync_master_timeout.cnf"
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_master_timeout.cnf" should include "rpl_semi_sync_master_timeout = 3000"
    End

    It "fails closed when an existing rpl_semi_sync_master_timeout override is invalid"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      printf '[mysqld]\nrpl_semi_sync_master_timeout = invalid\n' > "${overrides_dir}/rpl_semi_sync_master_timeout.cnf"
      When call run_seeder
      The status should equal 5
      The stderr should include "invalid existing rpl_semi_sync_master_timeout"
    End
  End

  Describe "async seeds all OFF / defaults"
    It "writes rpl_semi_sync_master_enabled=OFF"
      MARIADB_REPLICATION_MODE=async
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_master_enabled.cnf" should include "rpl_semi_sync_master_enabled = OFF"
    End

    It "writes rpl_semi_sync_slave_enabled=OFF"
      MARIADB_REPLICATION_MODE=async
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_slave_enabled.cnf" should include "rpl_semi_sync_slave_enabled = OFF"
    End
  End

  Describe "invalid mode fail-closed"
    It "exits with code 2 on unknown mode value"
      MARIADB_REPLICATION_MODE=bogus
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should equal 2
      The stderr should include "invalid"
      The stderr should include "bogus"
    End

    It "does NOT create override files on invalid mode"
      MARIADB_REPLICATION_MODE=garbage
      export MARIADB_REPLICATION_MODE
      run_seeder >/dev/null 2>&1 || true
      When call test "$(ls "${overrides_dir}" | wc -l | tr -d ' ')" -eq 0
      The status should be success
    End
  End

  Describe "missing overrides dir"
    It "exits with code 5 when MARIADB_RUNTIME_OVERRIDES_DIR does not exist"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      MARIADB_RUNTIME_OVERRIDES_DIR="/nonexistent/path/to/overrides"
      export MARIADB_RUNTIME_OVERRIDES_DIR
      When call run_seeder
      The status should equal 5
      The stderr should include "does not exist"
    End
  End

  Describe "idempotency — mtime preserved on repeated invocation"
    It "byte-equal short-circuit preserves mtime when override file is already at target"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      __SOURCED__=1 . "$(script_path)"
      seed_replication_mode_overrides
      first_mtime=$(stat -f "%m" "${overrides_dir}/rpl_semi_sync_master_enabled.cnf" 2>/dev/null || stat -c "%Y" "${overrides_dir}/rpl_semi_sync_master_enabled.cnf")
      sleep 1
      seed_replication_mode_overrides
      second_mtime=$(stat -f "%m" "${overrides_dir}/rpl_semi_sync_master_enabled.cnf" 2>/dev/null || stat -c "%Y" "${overrides_dir}/rpl_semi_sync_master_enabled.cnf")
      When call test "${first_mtime}" = "${second_mtime}"
      The status should be success
    End
  End

  Describe "convergence with reconfigureAction.persisted"
    # The seeder writes byte-identical content to what
    # reconfigureAction.persisted writes for the same env, so a later
    # reconfigure with the same mode does not rewrite the file (the
    # mapper + main loop's cmp -s short-circuit kicks in). Lock the
    # output shape so this convergence holds.
    It "writes only [mysqld] + name = value (no timestamp, no extra metadata)"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      run_seeder >/dev/null 2>&1
      # Each override file should be exactly 2 lines: [mysqld] + the
      # parameter assignment. No "Written on ..." timestamp line that
      # would change every write and defeat byte-equal compare.
      When call wc -l "${overrides_dir}/rpl_semi_sync_master_enabled.cnf"
      The output should include "2"
    End
  End

  Describe "script mount + cmpd wire-up (static contract)"
    cmpd_merged_path() {
      printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "$(repo_root)"
    }

    configmap_path() {
      printf "%s/addons/mariadb/templates/configmap-scripts-replication.yaml" "$(repo_root)"
    }

    It "configmap-scripts-replication.yaml mounts seed-replication-mode-overrides.sh"
      When call grep -c 'seed-replication-mode-overrides.sh' "$(configmap_path)"
      The status should be success
      The output should equal "2"
    End

    It "cmpd-replication.yaml invokes the seeder before mariadbd start"
      # The seeder must be sourced/invoked in the container command
      # body. Lock that it appears exactly once as a code line (the
      # explanatory comment textually references the script name).
      When call grep -cE '^[[:space:]]+sh /scripts/seed-replication-mode-overrides\.sh' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End

    It "cmpd-replication.yaml fails the container on seeder non-zero rc"
      When call grep -c 'refusing to start mariadbd' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "2"
    End

    # alpha.89 v1 commit 13 v3 (Helen 2026-05-20, Jack B3 fix msg
    # `6e6eab69`) — when MARIADB_REPLICATION_MODE is non-empty the
    # seeder script MUST be readable; missing script with non-empty
    # mode must fail-closed (no silent fallback to async).
    It "cmpd-replication.yaml fail-closes on missing seeder script when mode is non-empty (Jack B3 fix)"
      When call grep -c 'set but seeder script /scripts/seed-replication-mode-overrides.sh is missing or unreadable' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End

    It "cmpd-replication.yaml gates the missing-script check on non-empty MARIADB_REPLICATION_MODE"
      When call grep -cE 'if \[ -n "\$\{MARIADB_REPLICATION_MODE:-\}" \]' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End
  End

  Describe "B4 target type validation defense-in-depth Jack fix"
    # If a target path exists but is not a regular file (directory,
    # symlink-to-dir, device, fifo, socket), `mv tmp target` would
    # move tmp INTO the directory (for dir case) or silently overwrite
    # the wrong shape — leaving the target as a non-file with no
    # override content. The seeder MUST pre-validate target type
    # before any tmp write.

    It "fails with rc=5 when a target path exists as a directory"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      # commit 16: wait_for_slave_count was removed; use timeout
      # target as the directory-shape victim instead.
      mkdir "${overrides_dir}/rpl_semi_sync_master_timeout.cnf"
      When call run_seeder
      The status should equal 5
      The stderr should include "exists but is not a regular file"
    End

    It "does NOT write any tmp / override files when validation fails (no partial state)"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      mkdir "${overrides_dir}/rpl_semi_sync_master_timeout.cnf"
      run_seeder >/dev/null 2>&1 || true
      # No .cnf files written (the only thing in the dir is the
      # pre-created bogus dir target).
      regular_file_count=$(find "${overrides_dir}" -maxdepth 1 -type f -name '*.cnf' | wc -l | tr -d ' ')
      tmp_file_count=$(find "${overrides_dir}" -maxdepth 1 -type f -name '*.cnf.tmp.*' | wc -l | tr -d ' ')
      When call test "${regular_file_count}" -eq 0 -a "${tmp_file_count}" -eq 0
      The status should be success
    End
  End

  Describe "B5 partial-state protection Jack fix"
    # When a tmp write or rename fails partway through the 4-file
    # batch, the seeder must not leave any orphan tmp files behind.
    # On the very first failure, the seeder calls cleanup_all_tmps to
    # remove any tmp files that have already been written and returns
    # rc=5.

    # ShellSpec captures stderr globally for the `When call` block.
    # The seeder writes a "Permission denied" + sentinel to stderr
    # on a read-only-dir write failure, so we consume both via
    # `The stderr should include` to avoid "unexpected stderr" abort.
    It "cleans up all tmp files + returns rc=5 + no .cnf residue when a tmp write fails (read-only dir)"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      attempt_then_assert() {
        chmod 0555 "${overrides_dir}"
        local rc=0
        run_seeder >/dev/null 2>&1 || rc=$?
        chmod 0755 "${overrides_dir}"
        local tmp_residue=$(find "${overrides_dir}" -maxdepth 1 -name '*.cnf.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
        local cnf_residue=$(find "${overrides_dir}" -maxdepth 1 -name '*.cnf' -type f 2>/dev/null | wc -l | tr -d ' ')
        printf "rc=%s tmp=%s cnf=%s\n" "${rc}" "${tmp_residue}" "${cnf_residue}"
      }
      When call attempt_then_assert
      The status should be success
      The output should equal "rc=5 tmp=0 cnf=0"
    End
  End

End
