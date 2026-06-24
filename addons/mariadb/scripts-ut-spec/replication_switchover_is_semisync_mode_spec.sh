# shellcheck shell=sh

# Behavioral lock on the alpha.89 v1 commit 7 (C1 path topology
# merge) `is_semisync_mode` helper added to
# scripts/replication-switchover.sh. The helper is staged: no caller
# wires it in commit 7. This spec validates the read-only contract
# (0 = semisync ON, 1 = semisync OFF, 2 = undetermined / fail-closed)
# so future caller patches build on a stable surface.
#
# Strategy: stub MARIADB_CLIENT_BIN with a controllable shell script,
# source replication-switchover.sh with __SOURCED__=1, then invoke
# is_semisync_mode and assert its rc. The stub reads its own argv
# to decide what to print so we can simulate ON / OFF / unknown /
# client failure with a single fixture.

Describe "alpha.89 replication-switchover.sh is_semisync_mode"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  setup() {
    tmpdir=$(mktemp -d -t mariadb-issemisync-XXXXXX)
    stub_bin="${tmpdir}/mariadb-stub"
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  # Build a stub mariadb client that emits a fixed value for the
  # @@rpl_semi_sync_master_enabled query and returns 0. Caller passes
  # the desired output string (or "" for empty / "FAIL" for non-zero
  # rc).
  write_stub() {
    response="$1"
    case "${response}" in
      FAIL)
        cat >"${stub_bin}" <<'EOF'
#!/bin/sh
exit 2
EOF
        ;;
      *)
        cat >"${stub_bin}" <<EOF
#!/bin/sh
# Echo the canned value for any -e SELECT query.
printf '%s\n' "${response}"
EOF
        ;;
    esac
    chmod +x "${stub_bin}"
  }

  # Invoke is_semisync_mode after sourcing the switchover script with
  # __SOURCED__=1. Returns the rc on stdout for The output assertion.
  run_helper() {
    (
      export __SOURCED__=1
      export MARIADB_CLIENT_BIN="${stub_bin}"
      export MARIADB_ROOT_USER='root'
      export MARIADB_ROOT_PASSWORD='unused-by-stub'
      export MARIADB_CONNECT_TIMEOUT_SECONDS=3
      . "$(repo_root)/addons/mariadb/scripts/replication-switchover.sh"
      is_semisync_mode
      printf 'rc=%d\n' $?
    )
  }

  It "returns 0 (semisync ON) when engine reports literal ON"
    write_stub ON
    When call run_helper
    The output should equal "rc=0"
  End

  It "returns 0 (semisync ON) when engine reports literal 1"
    write_stub 1
    When call run_helper
    The output should equal "rc=0"
  End

  It "returns 0 (semisync ON) when engine reports literal on (lowercase)"
    write_stub on
    When call run_helper
    The output should equal "rc=0"
  End

  It "returns 1 (semisync OFF) when engine reports literal OFF"
    write_stub OFF
    When call run_helper
    The output should equal "rc=1"
  End

  It "returns 1 (semisync OFF) when engine reports literal 0"
    write_stub 0
    When call run_helper
    The output should equal "rc=1"
  End

  It "returns 1 (semisync OFF) when engine reports literal off (lowercase)"
    write_stub off
    When call run_helper
    The output should equal "rc=1"
  End

  It "returns 2 (undetermined / fail-closed) when engine reports an unrecognized literal"
    # A value outside {0,1,ON,OFF,on,off} must NOT be silently
    # mapped to one of the two known modes; force callers to treat
    # it as conservative fail-closed.
    write_stub MAYBE
    When call run_helper
    The output should equal "rc=2"
  End

  It "returns 2 (undetermined / fail-closed) when engine returns an empty row"
    write_stub ""
    When call run_helper
    The output should equal "rc=2"
  End

  It "returns 2 (undetermined / fail-closed) when the mariadb client exits non-zero"
    write_stub FAIL
    When call run_helper
    The output should equal "rc=2"
  End

End
