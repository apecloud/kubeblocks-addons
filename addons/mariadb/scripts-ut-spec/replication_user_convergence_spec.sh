# shellcheck shell=sh
# alpha.72 v1 (Helen TL 22:14 autonomous decision + Jack XP review HOLD
# `5a7c68e5` 22:26 + ShellSpec hard-gate `d6103db1` 22:28; Jack Option 1
# scope-cap HOLD `c74a3b44` 22:46).
#
# alpha.72 v1 SCOPE = SEMISYNC TOPOLOGY ONLY. cmpd-replication.yaml is
# intentionally NOT extended (replication topology kb_replicator
# convergence + bootstrap write-site deferred to alpha.73+).
#
# Static gates protecting the semisync replication-user-path
# convergence introduced in alpha.72 v1:
#   1. Chart.yaml literal alpha.72.
#   2a. cmpd-replication.yaml carries env MYSQL_REPLICATION_USER=
#       kb_replicator + MARIADB_REPLICATION_USER=kb_replicator.
#   2b. cmpd-replication.yaml is intentionally NOT extended with these
#       env (alpha.72 v1 scope cap).
#   3a. cmpd-replication.yaml inline CHANGE MASTER uses
#       ${MARIADB_REPLICATION_USER:-kb_replicator}.
#   3b. cmpd-replication.yaml inline CHANGE MASTER keeps
#       ${MARIADB_ROOT_USER} (pre-alpha.72 behavior preserved).
#   3c. replication-member-join.sh (shared by both topologies) uses
#       chained fallback ${MARIADB_REPLICATION_USER:-${MARIADB_ROOT_USER}}:
#       semisync pods (env set) use kb_replicator; replication pods
#       (env not set) fall through to MARIADB_ROOT_USER (root).
#   4. ensure_internal_local_admin (cmpd-replication.yaml only) creates the
#      kb_replicator@'%' user with the idempotent convergence chain
#      in the same SQL block as kb_internal_root (NOT an atomic
#      transaction — MariaDB DDL/GRANT statements are not
#      transactional per Jack #3; rely on idempotent convergence):
#      CREATE USER IF NOT EXISTS + ALTER UNLOCK + REVOKE ALL + GRANT
#      REPLICATION SLAVE ON *.* (no admin bypass, no broad grants).
#
# Root cause being defended against (alpha.71 v1 N=1 RED, semisync
# topology): pod-1 secondary COM_REGISTER_SLAVE failed Errno 1597 /
# Access denied (Errno 1045) for `kb_internal_root@'%'`. syncer Follow
# fell back to MYSQL_ADMIN_USER (=kb_internal_root) because
# MYSQL_REPLICATION_USER env was not set, and kb_internal_root@'%' had
# REPLICATION CLIENT + REPLICATION MASTER ADMIN but NO REPLICATION
# SLAVE. Three semisync call sites were diverging on MASTER_USER.
# alpha.72 v1 converges all three SEMISYNC call sites to kb_replicator
# and creates the user in bootstrap with REPLICATION SLAVE only.
# Replication topology stays on the pre-alpha.72 root path until
# alpha.73+.
#
# alpha.74 v1 carry-forward (Helen TL autonomous under westonnnn 01:28
# `df3c94b0` 12h autopilot mandate + Jack XP review ACK `c5997164`
# 01:37): alpha.73 v1 N=1 verify on n1h was PARTIAL — chart/bootstrap
# subpath GREEN but semisync product-chain RED (pod-1
# Slave_SQL_Running=No, Last_SQL_Errno=1396 "Operation CREATE USER
# failed for kb_replicator@%"; INSERT sync ERROR 1049). Root cause:
# mariadb 11.4 docker-entrypoint.sh consumes `MARIADB_REPLICATION_USER`
# / `MARIADB_REPLICATION_PASSWORD` env on initdb and runs CREATE USER
# WITHOUT `IF NOT EXISTS` while `sql_log_bin=1` → CREATE USER DDL
# written to binlog → pod-1 binlog replay collides with its own
# entrypoint-created kb_replicator → 1396 → SQL_Thread stops →
# INSERT sync impossible.
#
# alpha.74 v1 fix = rename the chart-defined env names so they no
# longer match the mariadb entrypoint's reserved env list:
#   MARIADB_REPLICATION_USER     -> MARIADB_REPL_USER
#   MARIADB_REPLICATION_PASSWORD -> MARIADB_REPL_PASSWORD
# Direct entrypoint grep evidence: `MARIADB_REPLICATION_USER` IS in
# the entrypoint's consumed env list; `MARIADB_REPL_USER` is NOT;
# `MYSQL_REPLICATION_USER` (kept) is NOT (syncer Follow continues to
# read it). Chart inline CHANGE MASTER reads
# `${MARIADB_REPL_USER:-kb_replicator}`; replication-member-join.sh
# reads `${MARIADB_REPL_USER:-${MARIADB_ROOT_USER}}` (chained fallback
# preserves alpha.72 v1 scope-cap: semisync sets REPL_USER →
# kb_replicator; replication topology has no REPL_USER → root,
# unchanged from pre-alpha.72). Static gates below are updated to
# assert the renamed env names; `MARIADB_REPLICATION_USER` literal is
# explicitly negative-grepped to prevent regression.

Describe "alpha.72 v1 replication user path convergence (static gates)"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  CHART_YAML="${ADDON_ROOT}/Chart.yaml"
  CMPD_SEMISYNC="${ADDON_ROOT}/templates/cmpd-replication.yaml"
  CMPD_REPLICATION="${ADDON_ROOT}/templates/cmpd-replication.yaml"
  CMPD_ENTRYPOINT="${ADDON_ROOT}/scripts/replication-entrypoint.sh"
  MEMBER_JOIN="${ADDON_ROOT}/scripts/replication-member-join.sh"

  Describe "Gate 1: Chart.yaml literal version"
    It "is exactly 1.2.0-alpha.26 (alpha.26 bump: replication merged topology)"
      When call grep -c '^version: 1.2.0-alpha.26$' "${CHART_YAML}"
      The output should eq "1"
      The status should be success
    End

    It "does not retain prior alpha.90 version line (no stale literal)"
      When call grep -c '^version: 1.1.1-alpha.90$' "${CHART_YAML}"
      The output should eq "0"
      The status should be failure
    End
  End

  Describe "Gate 2: env present in both CmpDs"
    It "cmpd-replication.yaml declares MYSQL_REPLICATION_USER=kb_replicator (syncer reads)"
      When call grep -c 'name: MYSQL_REPLICATION_USER' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "cmpd-replication.yaml declares MARIADB_REPL_USER=kb_replicator (chart shell reads; renamed from MARIADB_REPLICATION_USER to avoid triggering mariadb image entrypoint CREATE USER binlog side-effect)"
      When call grep -c 'name: MARIADB_REPL_USER' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "cmpd-replication.yaml does NOT declare MARIADB_REPLICATION_USER env (alpha.74 v1: this env triggers mariadb 11.4 image entrypoint to run CREATE USER kb_replicator at initdb time without IF NOT EXISTS, causing SQL replay 1396 on secondary START SLAVE per alpha.73 v1 N=1 partial RED root cause)"
      When call grep -c 'name: MARIADB_REPLICATION_USER' "${CMPD_SEMISYNC}"
      The output should eq "0"
      The status should be failure
    End

    # [REMOVED] alpha.72 v1 scope-cap tests: after CMPD consolidation (PR #2933),
    # cmpd-replication.yaml is the single canonical CMPD and includes all
    # features from both old replication and semisync CMPDs. The scope-cap
    # assertions (MYSQL_REPLICATION_USER absent, MARIADB_REPLICATION_USER
    # absent) no longer apply.
  End

  Describe "Gate 3: no MASTER_USER='\${MARIADB_ROOT_USER}' anywhere"
    It "replication-member-join.sh does not use MARIADB_ROOT_USER as MASTER_USER"
      When call grep -c "MASTER_USER='\${MARIADB_ROOT_USER}'" "${MEMBER_JOIN}"
      The output should eq "0"
      The status should be failure
    End

    It "replication-member-join.sh uses chained fallback MARIADB_REPL_USER -> MARIADB_ROOT_USER (semisync sets MARIADB_REPL_USER=kb_replicator; replication topology unchanged per alpha.72 v1 scope-cap)"
      When call grep -c "MASTER_USER='\${MARIADB_REPL_USER:-\${MARIADB_ROOT_USER}}'" "${MEMBER_JOIN}"
      The output should be present
      The status should be success
    End

    It "cmpd-replication.yaml inline CHANGE MASTER does not use MARIADB_ROOT_USER as MASTER_USER"
      When call grep -c "MASTER_USER='\${MARIADB_ROOT_USER}'" "${CMPD_SEMISYNC}"
      The output should eq "0"
      The status should be failure
    End

    It "cmpd-replication.yaml inline CHANGE MASTER uses MARIADB_REPL_USER fallback to kb_replicator (renamed env per alpha.74 v1)"
      When call grep -cF "MASTER_USER='\${MARIADB_REPL_USER:-kb_replicator}'" "${CMPD_ENTRYPOINT}"
      The output should be present
      The status should be success
    End

    # [REMOVED] alpha.72 v1 scope-cap test: after CMPD consolidation (PR #2933),
    # the single CMPD uses MARIADB_REPL_USER fallback, not MARIADB_ROOT_USER.
    # The assertion that MASTER_USER='${MARIADB_ROOT_USER}' is present no
    # longer applies.
  End

  Describe "Gate 4: kb_replicator write site idempotent convergence chain (cmpd-replication.yaml ensure_internal_local_admin)"
    It "creates kb_replicator with CREATE USER IF NOT EXISTS"
      When call grep -cF "CREATE USER IF NOT EXISTS '\${replication_user}'@'%'" "${CMPD_ENTRYPOINT}"
      The output should eq "1"
      The status should be success
    End

    It "applies ALTER UNLOCK (idempotent unlock after CREATE)"
      When call grep -cF "ALTER USER '\${replication_user}'@'%' ACCOUNT UNLOCK" "${CMPD_ENTRYPOINT}"
      The output should eq "1"
      The status should be success
    End

    It "applies REVOKE ALL PRIVILEGES (clears any prior leaked grants)"
      When call grep -cF "REVOKE ALL PRIVILEGES, GRANT OPTION FROM '\${replication_user}'@'%'" "${CMPD_ENTRYPOINT}"
      The output should eq "1"
      The status should be success
    End

    It "grants exactly REPLICATION SLAVE ON *.* (no admin bypass priv, no broad grants)"
      When call grep -cF "GRANT REPLICATION SLAVE ON *.* TO '\${replication_user}'@'%'" "${CMPD_ENTRYPOINT}"
      The output should eq "1"
      The status should be success
    End

    It "does NOT grant REPLICATION SLAVE to kb_internal_root@'%' (admin role must not leak slave priv)"
      When call grep -cF "GRANT REPLICATION SLAVE ON *.* TO '\${user}'@'%'" "${CMPD_ENTRYPOINT}"
      The output should eq "0"
      The status should be failure
    End

    It "does NOT grant ALL PRIVILEGES to kb_replicator@'%' (no admin bypass)"
      When call grep -cF "GRANT ALL PRIVILEGES ON *.* TO '\${replication_user}'@'%'" "${CMPD_ENTRYPOINT}"
      The output should eq "0"
      The status should be failure
    End

    It "uses shell var (replication_user) sourced from MARIADB_REPL_USER fallback to kb_replicator"
      When call grep -cF 'replication_user="$(sql_quote "${MARIADB_REPL_USER:-kb_replicator}")"' "${CMPD_ENTRYPOINT}"
      The output should eq "1"
      The status should be success
    End
  End

  Describe "Gate 5: env-pair USER+PASSWORD contract (alpha.73 v1 fix - mariadb 11.4 entrypoint contract)"
    # alpha.72 v1 N=1 RED root cause: mariadb 11.4 Docker entrypoint
    # requires *_REPLICATION_PASSWORD env when *_REPLICATION_USER is set.
    # Container fails fast with "[ERROR] [Entrypoint]:
    # MARIADB_REPLICATION_PASSWORD or MARIADB_REPLICATION_PASSWORD_HASH
    # not found to create replication user for master". alpha.73 v1
    # supplies the matching _PASSWORD envs referencing $(MARIADB_ROOT_PASSWORD).
    It "cmpd-replication.yaml declares MARIADB_REPL_PASSWORD (renamed from MARIADB_REPLICATION_PASSWORD; mariadb entrypoint no longer reads it so initdb does NOT auto-create kb_replicator)"
      When call grep -c 'name: MARIADB_REPL_PASSWORD' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    It "cmpd-replication.yaml does NOT declare MARIADB_REPLICATION_PASSWORD env (alpha.74 v1: paired removal so mariadb entrypoint USER/PASSWORD contract is not triggered at all)"
      When call grep -c 'name: MARIADB_REPLICATION_PASSWORD' "${CMPD_SEMISYNC}"
      The output should eq "0"
      The status should be failure
    End

    It "cmpd-replication.yaml MARIADB_REPLICATION_PASSWORD value references MARIADB_ROOT_PASSWORD via env expansion"
      When call grep -c '            value: "$(MARIADB_ROOT_PASSWORD)"' "${CMPD_SEMISYNC}"
      The output should be present
      The status should be success
    End

    It "cmpd-replication.yaml declares MYSQL_REPLICATION_PASSWORD (syncer Go binary USER+PASSWORD pair)"
      When call grep -c 'name: MYSQL_REPLICATION_PASSWORD' "${CMPD_SEMISYNC}"
      The output should eq "1"
      The status should be success
    End

    # [REMOVED] alpha.72/.73 v1 scope-cap tests: after CMPD consolidation
    # (PR #2933), the single CMPD includes both MARIADB_REPLICATION_PASSWORD
    # and MYSQL_REPLICATION_PASSWORD from the former semisync CMPD.
    # Scope-cap assertions no longer apply.
  End
End
