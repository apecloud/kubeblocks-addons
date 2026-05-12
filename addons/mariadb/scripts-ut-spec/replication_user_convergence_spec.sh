# shellcheck shell=sh
# alpha.72 v1 (Helen TL 22:14 autonomous decision + Jack XP review HOLD
# `5a7c68e5` 22:26 + ShellSpec hard-gate `d6103db1` 22:28).
#
# 4 minimum static gates protecting the replication-user-path convergence
# introduced in alpha.72 v1:
#   1. Chart.yaml literal alpha.72.
#   2. Both cmpd-semisync.yaml and cmpd-replication.yaml carry the env
#      MYSQL_REPLICATION_USER=kb_replicator + MARIADB_REPLICATION_USER=
#      kb_replicator.
#   3. No CHANGE MASTER TO call site uses MARIADB_ROOT_USER as MASTER_USER;
#      all three call sites (replication-member-join.sh + cmpd-semisync.yaml
#      inline + cmpd-replication.yaml inline) reference
#      ${MARIADB_REPLICATION_USER:-kb_replicator}.
#   4. ensure_internal_local_admin (cmpd-semisync.yaml) creates the
#      kb_replicator@'%' user with the idempotent convergence chain:
#      CREATE USER IF NOT EXISTS + ALTER UNLOCK + REVOKE ALL + GRANT
#      REPLICATION SLAVE ON *.* (no admin bypass, no broad grants).
#
# Root cause being defended against (alpha.71 v1 N=1 RED):
# pod-1 secondary COM_REGISTER_SLAVE failed Errno 1597 / Access denied
# (Errno 1045) for `kb_internal_root@'%'`. syncer Follow fell back to
# MYSQL_ADMIN_USER (=kb_internal_root) because MYSQL_REPLICATION_USER
# env was not set, and kb_internal_root@'%' had REPLICATION CLIENT +
# REPLICATION MASTER ADMIN but NO REPLICATION SLAVE. Three call sites
# were diverging on MASTER_USER. alpha.72 v1 converges all three sites
# to kb_replicator and creates the user in bootstrap with REPLICATION
# SLAVE only.

Describe "alpha.72 v1 replication user path convergence (static gates)"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  CHART_YAML="${ADDON_ROOT}/Chart.yaml"
  CMPD_SEMISYNC="${ADDON_ROOT}/templates/cmpd-semisync.yaml"
  CMPD_REPLICATION="${ADDON_ROOT}/templates/cmpd-replication.yaml"
  MEMBER_JOIN="${ADDON_ROOT}/scripts/replication-member-join.sh"

  Describe "Gate 1: Chart.yaml literal version"
    It "is exactly 1.1.1-alpha.72 (chart bump because CmpD spec mutates per KB immutability rule)"
      When call grep -c '^version: 1.1.1-alpha.72$' "${CHART_YAML}"
      The output should eq "1"
      The status should be success
    End

    It "does not retain prior alpha.71 version line (no stale literal)"
      When call grep -c '^version: 1.1.1-alpha.71$' "${CHART_YAML}"
      The output should eq "0"
      The status should be failure
    End
  End

  Describe "Gate 2: env present in both CmpDs"
    It "cmpd-semisync.yaml declares MYSQL_REPLICATION_USER=kb_replicator (syncer reads)"
      When call grep -c 'name: MYSQL_REPLICATION_USER' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "cmpd-semisync.yaml declares MARIADB_REPLICATION_USER=kb_replicator (chart shell reads)"
      When call grep -c 'name: MARIADB_REPLICATION_USER' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "cmpd-replication.yaml declares MYSQL_REPLICATION_USER=kb_replicator"
      When call grep -c 'name: MYSQL_REPLICATION_USER' "${CMPD_REPLICATION}"
      The output should eq "1"
      The status should be success
    End

    It "cmpd-replication.yaml declares MARIADB_REPLICATION_USER=kb_replicator"
      When call grep -c 'name: MARIADB_REPLICATION_USER' "${CMPD_REPLICATION}"
      The output should eq "1"
      The status should be success
    End
  End

  Describe "Gate 3: no MASTER_USER='\${MARIADB_ROOT_USER}' anywhere"
    It "replication-member-join.sh does not use MARIADB_ROOT_USER as MASTER_USER"
      When call grep -c "MASTER_USER='\${MARIADB_ROOT_USER}'" "${MEMBER_JOIN}"
      The output should eq "0"
      The status should be failure
    End

    It "replication-member-join.sh uses MARIADB_REPLICATION_USER fallback to kb_replicator"
      When call grep -c "MASTER_USER='\${MARIADB_REPLICATION_USER:-kb_replicator}'" "${MEMBER_JOIN}"
      The output should be present
      The status should be success
    End

    It "cmpd-semisync.yaml inline CHANGE MASTER does not use MARIADB_ROOT_USER as MASTER_USER"
      When call grep -c "MASTER_USER='\${MARIADB_ROOT_USER}'" "${CMPD_SEMISYNC}"
      The output should eq "0"
      The status should be failure
    End

    It "cmpd-semisync.yaml inline CHANGE MASTER uses MARIADB_REPLICATION_USER fallback to kb_replicator"
      When call grep -c "MASTER_USER='\${MARIADB_REPLICATION_USER:-kb_replicator}'" "${CMPD_SEMISYNC}"
      The output should be present
      The status should be success
    End

    It "cmpd-replication.yaml inline CHANGE MASTER does not use MARIADB_ROOT_USER as MASTER_USER"
      When call grep -c "MASTER_USER='\${MARIADB_ROOT_USER}'" "${CMPD_REPLICATION}"
      The output should eq "0"
      The status should be failure
    End

    It "cmpd-replication.yaml inline CHANGE MASTER uses MARIADB_REPLICATION_USER fallback to kb_replicator"
      When call grep -c "MASTER_USER='\${MARIADB_REPLICATION_USER:-kb_replicator}'" "${CMPD_REPLICATION}"
      The output should be present
      The status should be success
    End
  End

  Describe "Gate 4: kb_replicator write site idempotent convergence chain (cmpd-semisync.yaml ensure_internal_local_admin)"
    It "creates kb_replicator with CREATE USER IF NOT EXISTS"
      When call grep -c "CREATE USER IF NOT EXISTS '\${replication_user}'@'%'" "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "applies ALTER UNLOCK (idempotent unlock after CREATE)"
      When call grep -c "ALTER USER '\${replication_user}'@'%' ACCOUNT UNLOCK" "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "applies REVOKE ALL PRIVILEGES (clears any prior leaked grants)"
      When call grep -c "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '\${replication_user}'@'%'" "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "grants exactly REPLICATION SLAVE ON *.* (no admin bypass priv, no broad grants)"
      When call grep -c "GRANT REPLICATION SLAVE ON \*\.\* TO '\${replication_user}'@'%'" "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "does NOT grant REPLICATION SLAVE to kb_internal_root@'%' (admin role must not leak slave priv)"
      When call grep -c "GRANT REPLICATION SLAVE ON \*\.\* TO '\${user}'@'%'" "${CMPD_SEMISYNC}"
      The output should eq "0"
      The status should be failure
    End

    It "does NOT grant ALL PRIVILEGES to kb_replicator@'%' (no admin bypass)"
      When call grep -c "GRANT ALL PRIVILEGES ON \*\.\* TO '\${replication_user}'@'%'" "${CMPD_SEMISYNC}"
      The output should eq "0"
      The status should be failure
    End

    It "uses shell var (replication_user) sourced from MARIADB_REPLICATION_USER fallback to kb_replicator"
      When call grep -c 'replication_user="\$(sql_quote "\${MARIADB_REPLICATION_USER:-kb_replicator}")"' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End
  End
End
