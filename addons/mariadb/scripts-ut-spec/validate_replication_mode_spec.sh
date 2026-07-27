# shellcheck shell=sh

# Behavioral tests for scripts/validate-replication-mode.sh, the
# alpha.89 v1 commit 4 read-only two-source consistency check
# between the MariaDB engine's in-memory state (SHOW VARIABLES) and
# the rendered ConfigMap-mounted my.cnf. The script is invoked by
# test runners at closeout (and may later be wrapped by a kbagent
# action) to fail-closed when the engine and the desired state
# disagree.
#
# Strategy: stub the `mysql` binary by inserting a tmp dir at the
# front of PATH for each test, and point the script at a tmp my.cnf
# file via MARIADB_CONFIG_PATH. Run the script directly and check
# its exit code plus the key=value tokens it prints.

Describe "alpha.89 validate-replication-mode.sh"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mariadb/scripts/validate-replication-mode.sh" "$(repo_root)"
  }

  setup() {
    tmpdir=$(mktemp -d -t mariadb-validate-XXXXXX)
    cfg_path="${tmpdir}/my.cnf"
    bin_dir="${tmpdir}/bin"
    mkdir -p "${bin_dir}"
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  # Build a stub `mysql` that prints a tab-separated SHOW VARIABLES
  # row for the queried variable. Caller passes the master and slave
  # values; the stub reads its own `-e` query to decide which value
  # to emit.
  write_mysql_stub() {
    master_val="$1"
    slave_val="$2"
    cat >"${bin_dir}/mysql" <<EOF
#!/bin/sh
# Parse the -e flag's value to pick a response.
query=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -e) query="\$2"; shift 2 ;;
    -e*) query="\${1#-e}"; shift ;;
    *) shift ;;
  esac
done
case "\${query}" in
  *rpl_semi_sync_master_enabled*) printf 'rpl_semi_sync_master_enabled\t%s\n' "${master_val}" ;;
  *rpl_semi_sync_slave_enabled*)  printf 'rpl_semi_sync_slave_enabled\t%s\n'  "${slave_val}"  ;;
esac
EOF
    chmod +x "${bin_dir}/mysql"
  }

  # Build a stub `mysql` that fails (used for engine_missing path).
  write_mysql_stub_failing() {
    cat >"${bin_dir}/mysql" <<'EOF'
#!/bin/sh
exit 2
EOF
    chmod +x "${bin_dir}/mysql"
  }

  # Build a my.cnf with the four variables under [mysqld].
  write_cnf() {
    master_val="$1"
    slave_val="$2"
    cat >"${cfg_path}" <<EOF
[mysqld]
rpl_semi_sync_master_enabled = ${master_val}
rpl_semi_sync_slave_enabled = ${slave_val}
rpl_semi_sync_master_wait_for_slave_count = 1
rpl_semi_sync_master_timeout = 10000
EOF
  }

  run_script() {
    PATH="${bin_dir}:${PATH}" \
      MARIADB_CONFIG_PATH="${cfg_path}" \
      MARIADB_HOST=127.0.0.1 \
      MARIADB_PORT=3306 \
      sh "$(script_path)"
  }

  It "exits 0 with mode_consistency=ok when both sources are ON"
    write_mysql_stub ON ON
    write_cnf ON ON
    When call run_script
    The status should be success
    The output should include "mode_consistency=ok"
    The output should include "mode_engine_master_enabled=ON"
    The output should include "mode_configmap_master_enabled=ON"
  End

  It "exits 0 with mode_consistency=ok when both sources are OFF"
    write_mysql_stub OFF OFF
    write_cnf OFF OFF
    When call run_script
    The status should be success
    The output should include "mode_consistency=ok"
    The output should include "mode_engine_master_enabled=OFF"
    The output should include "mode_configmap_master_enabled=OFF"
  End

  It "normalizes ON / 1 / true as the same value across sources"
    # Engine returns "1" (some MariaDB builds), ConfigMap has "ON".
    write_mysql_stub 1 1
    write_cnf ON ON
    When call run_script
    The status should be success
    The output should include "mode_consistency=ok"
  End

  It "exits 1 with mode_consistency=disagree when engine ON but ConfigMap OFF"
    write_mysql_stub ON ON
    write_cnf OFF OFF
    When call run_script
    The status should equal 1
    The output should include "mode_consistency=disagree"
    The output should include "mode_engine_master_enabled=ON"
    The output should include "mode_configmap_master_enabled=OFF"
  End

  It "exits 2 with mode_consistency=engine_missing when mysql fails"
    write_mysql_stub_failing
    write_cnf ON ON
    When call run_script
    The status should equal 2
    The output should include "mode_consistency=engine_missing"
  End

  # Jack design review commit 4 v1 Blocker B1 — slave engine read
  # failure was previously classified as invariant_violated (when
  # master=ON) instead of engine_missing. Lock the corrected
  # classification with a focused stub that responds only to master.
  It "exits 2 with mode_consistency=engine_missing when slave engine read returns empty"
    cat >"${bin_dir}/mysql" <<'EOF'
#!/bin/sh
query=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -e) query="$2"; shift 2 ;;
    -e*) query="${1#-e}"; shift ;;
    *) shift ;;
  esac
done
case "${query}" in
  *rpl_semi_sync_master_enabled*) printf 'rpl_semi_sync_master_enabled\tON\n' ;;
  # slave query returns no row, matching a transient SHOW VARIABLES failure
  *rpl_semi_sync_slave_enabled*)  : ;;
esac
EOF
    chmod +x "${bin_dir}/mysql"
    write_cnf ON ON
    When call run_script
    The status should equal 2
    The output should include "mode_consistency=engine_missing"
  End

  # Jack design review commit 4 v1 Blocker B1 — ConfigMap missing
  # the slave key was previously classified as disagree. Lock the
  # corrected classification.
  It "exits 3 with mode_consistency=configmap_missing when my.cnf is missing the slave key"
    write_mysql_stub ON ON
    cat >"${cfg_path}" <<EOF
[mysqld]
rpl_semi_sync_master_enabled = ON
rpl_semi_sync_master_wait_for_slave_count = 1
rpl_semi_sync_master_timeout = 10000
EOF
    When call run_script
    The status should equal 3
    The output should include "mode_consistency=configmap_missing"
  End

  It "exits 3 with mode_consistency=configmap_missing when my.cnf is unreadable"
    write_mysql_stub ON ON
    # Point at a path that does not exist.
    cfg_path="${tmpdir}/does-not-exist.cnf"
    When call run_script
    The status should equal 3
    The output should include "mode_consistency=configmap_missing"
  End

  It "exits 4 with mode_consistency=invariant_violated when master ON but slave OFF"
    # MariaDB semisync requires master and slave to be aligned;
    # an asymmetric setting silently degrades to async.
    write_mysql_stub ON OFF
    write_cnf ON OFF
    When call run_script
    The status should equal 4
    The output should include "mode_consistency=invariant_violated"
  End

End
