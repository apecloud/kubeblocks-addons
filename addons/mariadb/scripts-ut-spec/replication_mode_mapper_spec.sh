# shellcheck shell=sh

# alpha.89 v1 commit 12 (Helen 2026-05-20, C3 design mapper) —
# Behavioral lock on scripts/replication-mode-mapper.sh, the addon-side
# mapper that translates the synthetic `replicationMode` ComponentSpec
# parameter into the four real engine variables BEFORE the merged
# replication CmpD's reconfigureAction.persisted main loop runs.
#
# Jack pre-loaded review criteria (dm:@Jack msg `3a0f5385` /
# `e8c80793` / `144afd93` / `2e93eb72`):
#
#   1. mapper is the unique consumer / writer of `replicationMode` —
#      synthetic key never lands in the rewritten parameter list, so
#      it can never reach SET GLOBAL or runtime-overrides.d/.
#   2. conflict detection runs BEFORE any file modification — when
#      user-supplied real var disagrees with derived value, mapper
#      exits non-zero and the parameter list is unchanged.
#   3. mapper failure produces NO partial state — invalid mode and
#      missing argument paths both leave the parameter list as-is.
#   4. only-4-vars path: when MARIADB_REPLICATION_MODE is empty / unset,
#      mapper is a no-op (return 0, parameter list untouched).
#   5. both-consistent is idempotent: user supplying both `replicationMode
#      =semisync` and matching real vars yields exactly one assignment
#      per real var; no duplicates; repeated mapper invocation produces
#      identical output.
#
# Strategy: source the script with __SOURCED__=1, then invoke
# apply_replication_mode_mapping with a tmp parameter file. Assert
# return code AND the exact rewritten file contents.

Describe "alpha.89 replication-mode-mapper.sh"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mariadb/scripts/replication-mode-mapper.sh" "$(repo_root)"
  }

  setup() {
    tmpdir=$(mktemp -d -t mariadb-mapper-XXXXXX)
    param_file="${tmpdir}/params.txt"
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_param_file() {
    # $@ — one `name=value` per arg.
    : >"${param_file}"
    for line in "$@"; do
      printf "%s\n" "${line}" >>"${param_file}"
    done
  }

  read_param_file() {
    cat "${param_file}"
  }

  # Source the mapper and call apply_replication_mode_mapping with
  # the configured MARIADB_REPLICATION_MODE env. ShellSpec captures
  # stdout, stderr, and exit code separately.
  run_mapper() {
    # shellcheck disable=SC1090
    __SOURCED__=1 . "$(script_path)"
    apply_replication_mode_mapping "${param_file}"
  }

  Describe "case 1 — only mode (mode set, no user-supplied real vars)"
    It "exits 0 and produces the 3 MariaDB-supported derived vars for mode=semisync"
      write_param_file
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_enabled=ON'
      The contents of file "${param_file}" should include 'rpl_semi_sync_slave_enabled=ON'
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_timeout=10000'
      # commit 16: wait_for_slave_count is MySQL-specific and breaks MariaDB.
      The contents of file "${param_file}" should not include 'rpl_semi_sync_master_wait_for_slave_count'
    End

    It "exits 0 and produces the 3 MariaDB-supported derived vars for mode=async (all OFF / defaults)"
      write_param_file
      MARIADB_REPLICATION_MODE=async
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_enabled=OFF'
      The contents of file "${param_file}" should include 'rpl_semi_sync_slave_enabled=OFF'
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_timeout=10000'
      The contents of file "${param_file}" should not include 'rpl_semi_sync_master_wait_for_slave_count'
    End

    It "does NOT leak the synthetic replicationmode key into the rewritten parameter list"
      write_param_file
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should not include 'replicationmode'
      The contents of file "${param_file}" should not include 'replicationMode'
    End
  End

  Describe "case 2 — only 4 vars (mode empty / unset)"
    It "is a no-op when MARIADB_REPLICATION_MODE is empty"
      write_param_file 'rpl_semi_sync_master_enabled=ON' 'rpl_semi_sync_slave_enabled=ON'
      pre_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      MARIADB_REPLICATION_MODE=""
      export MARIADB_REPLICATION_MODE
      run_mapper >/dev/null 2>&1
      rc=$?
      post_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      When call test "${rc}" -eq 0 -a "${pre_sha}" = "${post_sha}"
      The status should be success
    End

    It "is a no-op when MARIADB_REPLICATION_MODE is unset"
      write_param_file 'rpl_semi_sync_master_enabled=OFF' 'rpl_semi_sync_master_timeout=5000'
      pre_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      unset MARIADB_REPLICATION_MODE
      run_mapper >/dev/null 2>&1
      rc=$?
      post_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      When call test "${rc}" -eq 0 -a "${pre_sha}" = "${post_sha}"
      The status should be success
    End
  End

  Describe "case 3 — both consistent (mode + matching real vars)"
    It "preserves user-supplied vars and appends only the missing derived vars"
      write_param_file 'rpl_semi_sync_master_enabled=ON' 'rpl_semi_sync_slave_enabled=ON'
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_enabled=ON'
      The contents of file "${param_file}" should include 'rpl_semi_sync_slave_enabled=ON'
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_timeout=10000'
      The contents of file "${param_file}" should not include 'rpl_semi_sync_master_wait_for_slave_count'
    End

    It "does not duplicate the user-supplied master_enabled line"
      # If the rewrite duplicated the user-supplied master_enabled
      # line, the count of matching lines would exceed 1. Lock to
      # exactly 1 by running the mapper, then counting matching lines
      # via grep.
      write_param_file 'rpl_semi_sync_master_enabled=ON' 'rpl_semi_sync_slave_enabled=ON'
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      run_mapper >/dev/null 2>&1
      master_count=$(grep -c '^rpl_semi_sync_master_enabled=' "${param_file}")
      slave_count=$(grep -c '^rpl_semi_sync_slave_enabled=' "${param_file}")
      When call test "${master_count}" -eq 1 -a "${slave_count}" -eq 1
      The status should be success
    End

    It "is idempotent — second invocation produces identical content (byte-equal)"
      write_param_file
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      __SOURCED__=1 . "$(script_path)"
      apply_replication_mode_mapping "${param_file}"
      first_pass_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      apply_replication_mode_mapping "${param_file}"
      second_pass_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      When call test "${first_pass_sha}" = "${second_pass_sha}"
      The status should be success
    End
  End

  Describe "case 4 — both conflict (mode + disagreeing real var)"
    It "exits non-zero (code 3) and emits a clear conflict message to stderr"
      write_param_file 'rpl_semi_sync_master_enabled=OFF'
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should equal 3
      The stderr should include 'conflict'
      The stderr should include 'rpl_semi_sync_master_enabled=ON'
      The stderr should include 'rpl_semi_sync_master_enabled=OFF'
    End

    It "leaves the parameter list UNCHANGED on conflict (fail-before-write contract)"
      write_param_file 'rpl_semi_sync_master_enabled=OFF' 'rpl_semi_sync_slave_enabled=OFF'
      pre_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      run_mapper >/dev/null 2>&1 || true
      post_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      When call test "${pre_sha}" = "${post_sha}"
      The status should be success
    End

    It "detects conflict on rpl_semi_sync_slave_enabled too"
      write_param_file 'rpl_semi_sync_slave_enabled=OFF'
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should equal 3
      The stderr should include 'rpl_semi_sync_slave_enabled'
    End
  End

  Describe "case 5 — mapper failure (invalid mode + bad arg)"
    It "exits non-zero (code 2) on an unknown mode value"
      write_param_file
      MARIADB_REPLICATION_MODE=bogus
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should equal 2
      The stderr should include 'invalid'
      The stderr should include 'bogus'
    End

    It "leaves the parameter list UNCHANGED on invalid mode (fail-before-write contract)"
      write_param_file 'rpl_semi_sync_master_enabled=ON'
      pre_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      MARIADB_REPLICATION_MODE=garbage
      export MARIADB_REPLICATION_MODE
      run_mapper >/dev/null 2>&1 || true
      post_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      When call test "${pre_sha}" = "${post_sha}"
      The status should be success
    End

    It "exits non-zero (code 4) when the parameter file argument is missing"
      # shellcheck disable=SC1090
      __SOURCED__=1 . "$(script_path)"
      When call apply_replication_mode_mapping ""
      The status should equal 4
      The stderr should include 'missing or unreadable'
    End

    It "exits non-zero (code 4) when the parameter file does not exist"
      # shellcheck disable=SC1090
      __SOURCED__=1 . "$(script_path)"
      When call apply_replication_mode_mapping "/nonexistent/path/params.txt"
      The status should equal 4
      The stderr should include 'missing or unreadable'
    End
  End

  Describe "synthetic key strip (defense-in-depth backstop)"
    It "strips a synthetic replicationMode line even when mode env is also set"
      write_param_file 'replicationMode=semisync' 'rpl_semi_sync_master_enabled=ON' 'rpl_semi_sync_slave_enabled=ON'
      MARIADB_REPLICATION_MODE=semisync
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should not include 'replicationMode'
      The contents of file "${param_file}" should not include 'replicationmode'
    End

    It "strips a lowercase replicationmode line too (KB INI parser lowercases keys)"
      write_param_file 'replicationmode=async' 'rpl_semi_sync_master_enabled=OFF' 'rpl_semi_sync_slave_enabled=OFF'
      MARIADB_REPLICATION_MODE=async
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should not include 'replicationmode'
      The contents of file "${param_file}" should not include 'replicationMode'
    End

    # alpha.89 v1 commit 12 v2 (Helen 2026-05-20, Jack B2 fix msg
    # `008885e2`) — UNCONDITIONAL strip means the synthetic key is
    # removed even when MARIADB_REPLICATION_MODE is unset/empty. The
    # earlier commit 12 v1 placed the strip after the empty-mode
    # early return, so a parameter list with a stray
    # `replicationMode=semisync` line and no env mode would silently
    # leave the synthetic key in place.
    It "strips replicationMode even when MARIADB_REPLICATION_MODE is unset (Jack B2 fix)"
      write_param_file 'replicationMode=semisync' 'rpl_semi_sync_master_enabled=ON'
      unset MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should not include 'replicationMode'
      The contents of file "${param_file}" should not include 'replicationmode'
      The contents of file "${param_file}" should include 'rpl_semi_sync_master_enabled=ON'
    End

    It "strips lowercase replicationmode even when MARIADB_REPLICATION_MODE is empty (Jack B2 fix)"
      write_param_file 'replicationmode=async' 'rpl_semi_sync_slave_enabled=OFF'
      MARIADB_REPLICATION_MODE=""
      export MARIADB_REPLICATION_MODE
      When call run_mapper
      The status should be success
      The contents of file "${param_file}" should not include 'replicationmode'
      The contents of file "${param_file}" should not include 'replicationMode'
      The contents of file "${param_file}" should include 'rpl_semi_sync_slave_enabled=OFF'
    End

    It "preserves mtime for clean only-4-vars input even with the unconditional strip"
      # When the input is clean (no synthetic key), strip is a no-op
      # and the param file's mtime is preserved.
      write_param_file 'rpl_semi_sync_master_enabled=ON' 'rpl_semi_sync_slave_enabled=ON'
      pre_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      unset MARIADB_REPLICATION_MODE
      run_mapper >/dev/null 2>&1
      rc=$?
      post_sha=$(shasum -a 256 "${param_file}" | awk '{print $1}')
      When call test "${rc}" -eq 0 -a "${pre_sha}" = "${post_sha}"
      The status should be success
    End
  End

  Describe "unique-call-site contract (rendered helper inspection)"
    # Jack contract item 1 (msg `e8c80793`): mapper must be the unique
    # consumer / writer of `replicationMode`. Lock by counting the
    # number of `apply_replication_mode_mapping` invocations in the
    # rendered persisted helper body. Sourcing must happen exactly
    # once per CmpD that includes the persisted variant.
    helper_path() {
      printf "%s/addons/mariadb/templates/_helpers.tpl" "$(repo_root)"
    }

    It "_helpers.tpl declares apply_replication_mode_mapping exactly once as the call site"
      When call grep -c 'apply_replication_mode_mapping "\${parameter_file}"' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "_helpers.tpl sources /scripts/replication-mode-mapper.sh exactly once"
      When call grep -c '__SOURCED__=1 \. /scripts/replication-mode-mapper.sh' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "_helpers.tpl gates the mapper call on file readability so non-merged topologies are safe no-ops"
      When call grep -c 'if \[ -r /scripts/replication-mode-mapper.sh \]' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "_helpers.tpl exits non-zero when the mapper returns non-zero (fail-closed)"
      When call grep -c 'replicationMode mapper failed' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    # alpha.89 v1 commit 12 v2 (Helen 2026-05-20, Jack B1 fix msg
    # `008885e2`) — `if ! apply_replication_mode_mapping ...; then
    # mapper_rc=$?` loses the original rc because `!` inverts the
    # exit code, so `$?` inside the then-block is 0 not the mapper's
    # 2/3/4/5. The fix preserves the rc via `|| mapper_rc=$?`.
    It "_helpers.tpl does NOT use the rc-losing 'if ! apply_replication_mode_mapping' antipattern as code (comments excluded)"
      # Match only code lines (no leading `#`) to avoid false positives
      # from the fix rationale comment that textually references the
      # earlier antipattern. The grep regex skips lines whose first
      # non-whitespace char is `#`.
      When call grep -cE '^[[:space:]]*[^#[:space:]].*if ! apply_replication_mode_mapping' "$(helper_path)"
      The status should be failure
      The output should equal "0"
    End

    It "_helpers.tpl preserves the mapper's original rc via '|| mapper_rc=\$?' (Jack B1 fix)"
      When call grep -c 'apply_replication_mode_mapping "\${parameter_file}" || mapper_rc=\$?' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "_helpers.tpl checks mapper_rc -ne 0 after the call (rc-aware fail-closed)"
      When call grep -c 'if \[ "\${mapper_rc}" -ne 0 \]' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End
  End

  Describe "byte-equal short-circuit in main loop (idempotency guard)"
    # Jack contract item (msg `2e93eb72`): the short-circuit must run
    # AFTER safety validation AND AFTER conflict detection (the mapper
    # runs first and exits before main loop), but BEFORE the atomic
    # mv. Lock the textual ordering.
    helper_path() {
      printf "%s/addons/mariadb/templates/_helpers.tpl" "$(repo_root)"
    }

    It "_helpers.tpl uses cmp -s on override_tmp vs override_file before mv"
      When call grep -c 'cmp -s "\${override_tmp}" "\${override_file}"' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "_helpers.tpl removed the alpha.86 timestamp line so equal-content overrides byte-compare identical"
      # The alpha.86 helper wrote `# Written by reconfigureAction.persisted on $(date -u ...)`
      # as the first override line. That timestamp made every rewrite
      # byte-different from the previous file, defeating cmp -s. The
      # commit 12 helper removes the timestamp comment.
      When call grep -c '# Written by reconfigureAction.persisted on' "$(helper_path)"
      The status should be failure
      The output should equal "0"
    End
  End

End
