# shellcheck shell=sh
#
# E1 contract: the mariadbd command line must start fail-closed with a
# PORTABLE read_only value. NO_LOCK_NO_ADMIN is a runtime-variable enum,
# not a valid command-line boolean — my_getopt does not recognize it and
# silently sets read_only=OFF on every shipped version (verified on
# mariadb 11.4 AND 11.8 via `mariadbd --read-only=NO_LOCK_NO_ADMIN
# --verbose --help` → "boolean value 'NO_LOCK_NO_ADMIN' wasn't recognized.
# Set to OFF."), turning fail-closed intent into a fail-open startup window.
# The SQL path (set_fail_closed_read_only) keeps the NO_LOCK_NO_ADMIN →
# ON → 1 tiering for the stronger runtime fence where the engine supports it.

Describe "replication-entrypoint read_only fail-closed startup contract"
  ENTRYPOINT="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-entrypoint.sh"

  extract_mariadbd_launch() {
    # The bootstrap launch: from the `docker-entrypoint.sh mariadbd \`
    # line to the line ending the backslash-continued argv (bind-address).
    awk '
      /docker-entrypoint\.sh mariadbd \\/ { in_cmd = 1 }
      in_cmd { print }
      in_cmd && /--bind-address=/ { exit }
    ' "${ENTRYPOINT}"
  }

  It "starts mariadbd with the portable boolean --read-only=ON"
    When call extract_mariadbd_launch
    The status should be success
    The output should include "--read-only=ON"
  End

  It "does NOT pass the non-portable enum NO_LOCK_NO_ADMIN on the command line"
    When call extract_mariadbd_launch
    The status should be success
    The output should not include "--read-only=NO_LOCK_NO_ADMIN"
  End

  It "keeps the SQL fail-closed helper tiering NO_LOCK_NO_ADMIN -> ON -> 1"
    # Runtime fence via SQL retains the stronger value where supported,
    # then falls back to ON and 1 (both universally valid).
    When run sh -c "grep -A12 'set_fail_closed_read_only()' '${ENTRYPOINT}'"
    The status should be success
    The output should include "SET GLOBAL read_only = NO_LOCK_NO_ADMIN;"
    The output should include "SET GLOBAL read_only = ON;"
    The output should include "SET GLOBAL read_only = 1;"
  End
End
