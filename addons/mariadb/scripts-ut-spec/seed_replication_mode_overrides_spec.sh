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

    It "writes rpl_semi_sync_master_wait_for_slave_count=1"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_master_wait_for_slave_count.cnf" should include "rpl_semi_sync_master_wait_for_slave_count = 1"
    End

    It "writes rpl_semi_sync_master_timeout=10000"
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_seeder
      The status should be success
      The contents of file "${overrides_dir}/rpl_semi_sync_master_timeout.cnf" should include "rpl_semi_sync_master_timeout = 10000"
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
      printf "%s/addons/mariadb/templates/cmpd-replication-merged.yaml" "$(repo_root)"
    }

    configmap_path() {
      printf "%s/addons/mariadb/templates/configmap-scripts-replication.yaml" "$(repo_root)"
    }

    It "configmap-scripts-replication.yaml mounts seed-replication-mode-overrides.sh"
      When call grep -c 'seed-replication-mode-overrides.sh' "$(configmap_path)"
      The status should be success
      The output should equal "2"
    End

    It "cmpd-replication-merged.yaml invokes the seeder before mariadbd start"
      # The seeder must be sourced/invoked in the container command
      # body. Lock that it appears exactly once as a code line (the
      # explanatory comment textually references the script name).
      When call grep -cE '^[[:space:]]+sh /scripts/seed-replication-mode-overrides\.sh' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End

    It "cmpd-replication-merged.yaml fails the container on seeder non-zero rc"
      When call grep -c 'refusing to start mariadbd' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End
  End

End
