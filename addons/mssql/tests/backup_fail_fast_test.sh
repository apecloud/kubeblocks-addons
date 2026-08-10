#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Static / script-level test for backup fail-fast semantics (backup.sh and
# incremental-backup.sh). No live SQL Server: a mock sqlcmd on PATH answers the
# database-list query and makes exactly one database's BACKUP fail with a T-SQL
# error. The backup action runs as common.sh + <backup script> concatenated
# (see templates/actionset*.yaml), which this test reproduces.
#
# Asserts: any single database failure fails the whole action (non-zero exit),
# the error names the failing database, and the success path (push_backups /
# save_backup_status) is NOT reached -- an incomplete backup is never reported
# as successful.

set -u

DP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../dataprotection" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- mock sqlcmd: extract the -Q query and respond by content -----------------
MOCKBIN="$TMP/bin"
mkdir -p "$MOCKBIN"
# FAIL_DB (env) names the database whose BACKUP fails; empty => all succeed.
cat > "$MOCKBIN/sqlcmd" <<'MOCK'
#!/usr/bin/env bash
q=""
while [ $# -gt 0 ]; do
  case "$1" in
    -Q) q="$2"; shift 2;;
    *) shift;;
  esac
done
case "$q" in
  *"CONVERT(varchar(max)"*)            printf '640062005f006f006b003100\n640062005f00620061006400\n640062005f006f006b003200\n';;
  *"role_desc"*)                       printf 'PRIMARY\n';;            # copy_only: primary -> no COPY_ONLY
  *"backupmediaset"*)                  : ;;                             # need_full_backup: no prior full -> full path
  *"BACKUP DATABASE"*)
    # The production SQL quotes database identifiers. Anchor the exact quoted
    # identifier at the start to avoid a false match on a substring name.
    expected_identifier="${FAIL_DB//]/]]}"
    if [ -n "${FAIL_DB:-}" ] && [[ "$q" == "BACKUP DATABASE [${expected_identifier}]"* ]]; then
      printf 'Msg 3201, Level 16, State 1, Server x, Line 1\nCannot open backup device. Operating system error 5(Access is denied.).\n'
    else
      printf 'Processed 100 pages...\nBACKUP DATABASE successfully processed 100 pages.\n'
    fi
    ;;
  *) : ;;
esac
exit 0
MOCK
chmod +x "$MOCKBIN/sqlcmd"

# datasafed / push helpers must never be reached on the failure path; stub them
# to a sentinel so we can prove the success path did not run.
SUCCESS_SENTINEL="$TMP/success_reached"
DATASAFED="$MOCKBIN/datasafed"
cat > "$DATASAFED" <<MOCK
#!/usr/bin/env bash
touch "$SUCCESS_SENTINEL"
exit 0
MOCK
chmod +x "$DATASAFED"

run_backup() { # <script> <fail_db>
  local script="$1" fail_db="$2"
  rm -f "$SUCCESS_SENTINEL"
  local body out rc
  body="$(cat "$DP_DIR/common.sh")"$'\n'"$(cat "$DP_DIR/$script")"
  out=$(
    PATH="$MOCKBIN:$PATH" FAIL_DB="$fail_db" \
    DP_DB_HOST=localhost DP_DB_USER=sa DP_DB_PASSWORD=x \
    DP_DATASAFED_BIN_PATH="$MOCKBIN" DP_BACKUP_BASE_PATH="$TMP/repo" \
    DP_BACKUP_NAME=bk1 BACKUP_DIR="$TMP/backups" DP_BACKUP_INFO_FILE="$TMP/info" \
    bash -c "$body" 2>&1
  )
  rc=$?
  RUN_OUT="$out"; RUN_RC="$rc"
}

pass=0; fail=0

# Negative: a middle database fails -> whole action fails, before the push path.
check_fail_fast() { # <script> <label>
  local script="$1" label="$2"
  run_backup "$script" db_bad
  if [ "$RUN_RC" -ne 0 ] \
     && printf '%s' "$RUN_OUT" | grep -q 'db_bad' \
     && printf '%s' "$RUN_OUT" | grep -qiE 'fail' \
     && [ ! -f "$SUCCESS_SENTINEL" ]; then
    echo "PASS  [fail-fast] $label (rc=$RUN_RC, names db_bad, push path not reached)"; pass=$((pass+1))
  else
    echo "FAIL  [fail-fast] $label (rc=$RUN_RC, sentinel=$( [ -f "$SUCCESS_SENTINEL" ] && echo present || echo absent ))"
    printf '%s\n' "$RUN_OUT" | sed 's/^/      /'; fail=$((fail+1))
  fi
}

# Positive: all databases succeed -> loop completes and reaches the push path
# (proves we did not break the happy path, incl. the incremental
# backup_database success-return fix). The stubbed backup_certificate exits
# non-zero afterwards, so we assert "push reached + no fail-fast", not exit 0.
check_happy_reaches_push() { # <script> <label>
  local script="$1" label="$2"
  run_backup "$script" ""
  if [ -f "$SUCCESS_SENTINEL" ] \
     && ! printf '%s' "$RUN_OUT" | grep -q 'failing the backup action'; then
    echo "PASS  [happy] $label (all succeed -> reached push, no fail-fast)"; pass=$((pass+1))
  else
    echo "FAIL  [happy] $label (sentinel=$( [ -f "$SUCCESS_SENTINEL" ] && echo present || echo absent ))"
    printf '%s\n' "$RUN_OUT" | sed 's/^/      /'; fail=$((fail+1))
  fi
}

check_fail_fast          backup.sh             "backup.sh: one failing database fails the whole action"
check_fail_fast          incremental-backup.sh "incremental-backup.sh: one failing database fails the whole action"
check_happy_reaches_push backup.sh             "backup.sh: all databases succeed"
check_happy_reaches_push incremental-backup.sh "incremental-backup.sh: all databases succeed"

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
