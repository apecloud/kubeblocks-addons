# shellcheck shell=sh

Describe "reconcile-runtime-overrides.sh"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mariadb/scripts/reconcile-runtime-overrides.sh" "$(repo_root)"
  }

  setup() {
    tmpdir=$(mktemp -d -t mariadb-reconcile-XXXXXX)
    overrides_dir="${tmpdir}/overrides"
    configmap_dir="${tmpdir}/conf.d"
    mkdir -p "${overrides_dir}" "${configmap_dir}"
    MARIADB_RUNTIME_OVERRIDES_DIR="${overrides_dir}"
    MARIADB_CONFIGMAP_PATH="${configmap_dir}/my.cnf"
    export MARIADB_RUNTIME_OVERRIDES_DIR MARIADB_CONFIGMAP_PATH
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  run_reconcile() {
    # shellcheck disable=SC1090
    __SOURCED__=1 . "$(script_path)"
    reconcile_runtime_overrides
  }

  write_configmap() {
    cat > "${MARIADB_CONFIGMAP_PATH}"
  }

  write_override() {
    param_name="$1"
    param_value="$2"
    printf '[mysqld]\n%s = %s\n' "${param_name}" "${param_value}" > "${overrides_dir}/${param_name}.cnf"
  }

  read_override() {
    param_name="$1"
    awk '
      /^\[/ { next }
      /^[[:space:]]*$/ { next }
      {
        idx = index($0, "=")
        val = substr($0, idx + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        print val
        exit
      }
    ' "${overrides_dir}/${param_name}.cnf"
  }

  Describe "no override files (no-op)"
    It "returns 0 when overrides dir is empty"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
EOF
      When call run_reconcile
      The status should eq 0
    End
  End

  Describe "no ConfigMap file (no-op)"
    It "returns 0 when ConfigMap path does not exist"
      rm -f "${MARIADB_CONFIGMAP_PATH}"
      write_override "long_query_time" "3"
      When call run_reconcile
      The status should eq 0
      The output should not include "reconcile-runtime-overrides"
    End
  End

  Describe "override matches ConfigMap (no-op)"
    It "leaves override unchanged when values already match"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
EOF
      write_override "long_query_time" "7"
      When call run_reconcile
      The status should eq 0
      The output should not include "reconcile-runtime-overrides:"
    End
  End

  Describe "stale override reconciled to ConfigMap"
    It "updates override to match ConfigMap value"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
slow_query_log = ON
EOF
      write_override "long_query_time" "3"
      When call run_reconcile
      The status should eq 0
      The output should include "long_query_time override '3' -> '7'"
    End

    It "override file contains the ConfigMap value after reconciliation"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
EOF
      write_override "long_query_time" "3"
      run_reconcile >/dev/null 2>&1
      When call read_override "long_query_time"
      The output should eq "7"
    End
  End

  Describe "override for param NOT in ConfigMap (left alone)"
    It "does not modify override when param is absent from ConfigMap"
      write_configmap <<'EOF'
[mysqld]
slow_query_log = ON
EOF
      write_override "rpl_semi_sync_master_timeout" "3000"
      run_reconcile >/dev/null 2>&1
      When call read_override "rpl_semi_sync_master_timeout"
      The output should eq "3000"
    End
  End

  Describe "multiple overrides with mixed match/mismatch"
    It "reconciles only mismatched overrides"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
slow_query_log = ON
wait_timeout = 90
EOF
      write_override "long_query_time" "3"
      write_override "slow_query_log" "ON"
      write_override "wait_timeout" "60"
      write_override "rpl_semi_sync_master_enabled" "ON"
      When call run_reconcile
      The status should eq 0
      The output should include "long_query_time override '3' -> '7'"
      The output should include "wait_timeout override '60' -> '90'"
      The output should not include "slow_query_log override"
      The output should not include "rpl_semi_sync_master_enabled"
    End

    It "file values are correct after mixed reconciliation"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
slow_query_log = ON
wait_timeout = 90
EOF
      write_override "long_query_time" "3"
      write_override "slow_query_log" "ON"
      write_override "wait_timeout" "60"
      write_override "rpl_semi_sync_master_enabled" "ON"
      run_reconcile >/dev/null 2>&1
      When call read_override "long_query_time"
      The output should eq "7"
    End

    It "non-ConfigMap override is preserved after mixed reconciliation"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
EOF
      write_override "long_query_time" "3"
      write_override "rpl_semi_sync_master_enabled" "ON"
      run_reconcile >/dev/null 2>&1
      When call read_override "rpl_semi_sync_master_enabled"
      The output should eq "ON"
    End
  End

  Describe "overrides dir missing"
    It "returns 1 when overrides dir does not exist"
      rmdir "${overrides_dir}"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 7
EOF
      When call run_reconcile
      The status should eq 1
      The error should include "overrides dir"
    End
  End

  Describe "ConfigMap with hyphenated param name"
    It "normalizes hyphens to underscores for matching"
      write_configmap <<'EOF'
[mysqld]
innodb-lock-wait-timeout = 30
EOF
      write_override "innodb_lock_wait_timeout" "50"
      run_reconcile >/dev/null 2>&1
      When call read_override "innodb_lock_wait_timeout"
      The output should eq "30"
    End
  End

  Describe "ConfigMap last-value-wins"
    It "uses the last occurrence when param appears multiple times"
      write_configmap <<'EOF'
[mysqld]
long_query_time = 3
long_query_time = 7
EOF
      write_override "long_query_time" "3"
      run_reconcile >/dev/null 2>&1
      When call read_override "long_query_time"
      The output should eq "7"
    End
  End

  Describe "script mount check"
    It "configmap-scripts-replication.yaml includes reconcile-runtime-overrides.sh"
      configmap_path() {
        printf "%s/addons/mariadb/templates/configmap-scripts-replication.yaml" "$(repo_root)"
      }
      When call grep -c 'reconcile-runtime-overrides.sh' "$(configmap_path)"
      The output should eq "2"
    End

    It "cmpd-replication.yaml invokes reconcile-runtime-overrides.sh"
      cmpd_path() {
        printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "$(repo_root)"
      }
      When call grep -c 'reconcile-runtime-overrides.sh' "$(cmpd_path)"
      The output should not eq "0"
    End

    It "cmpd-replication.yaml invokes reconcile-runtime-overrides.sh"
      cmpd_path() {
        printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "$(repo_root)"
      }
      When call grep -c 'reconcile-runtime-overrides.sh' "$(cmpd_path)"
      The output should not eq "0"
    End
  End

End
