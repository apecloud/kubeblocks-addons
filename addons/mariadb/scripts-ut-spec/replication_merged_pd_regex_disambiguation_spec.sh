# shellcheck shell=sh

# Lock that the four MariaDB ParametersDefinition componentDef regexes
# rendered by the alpha.89 topology merge scaffolding are mutually
# exclusive across the five rendered CmpD names. Jack design review
# (2026-05-19 15:42) flagged the previous wide regex
# `^mariadb-replication-` would silently match the new merged CmpD
# `mariadb-replication-merged-{ChartVersion}` and double-bind it to
# the deprecated PD. This spec encodes the disambiguation contract
# so future edits to either the helpers or paramsdef cannot silently
# reintroduce the overlap.

Describe "alpha.89 PD regex disambiguation"

  # Returns 0 (true) when $1 matches the POSIX ERE in $2, else 1.
  # Uses a portable awk path so the spec stays runner-agnostic.
  ere_matches() {
    awk -v s="$1" -v p="$2" 'BEGIN { exit !(s ~ p) }'
  }

  # The exact regex literals defined in
  # addons/mariadb/templates/_helpers.tpl post-alpha.89-v1.
  STANDALONE_RE='^mariadb-[0-9]'
  GALERA_RE='^mariadb-galera-'
  OLD_REPL_RE='^mariadb-replication-[0-9]'
  OLD_SEMISYNC_RE='^mariadb-semisync-'
  MERGED_RE='^mariadb-replication-merged-'

  # The five concrete CmpD names rendered at version 1.1.1-alpha.90.
  STANDALONE_NAME='mariadb-1.1.1-alpha.90'
  GALERA_NAME='mariadb-galera-1.1.1-alpha.90'
  OLD_REPL_NAME='mariadb-replication-1.1.1-alpha.90'
  OLD_SEMISYNC_NAME='mariadb-semisync-1.1.1-alpha.90'
  MERGED_NAME='mariadb-replication-merged-1.1.1-alpha.90'

  Describe "standalone CmpD name"
    It "matches only the standalone regex"
      When call ere_matches "$STANDALONE_NAME" "$STANDALONE_RE"
      The status should be success
    End
    It "does not match galera"
      When call ere_matches "$STANDALONE_NAME" "$GALERA_RE"
      The status should be failure
    End
    It "does not match old replication"
      When call ere_matches "$STANDALONE_NAME" "$OLD_REPL_RE"
      The status should be failure
    End
    It "does not match old semisync"
      When call ere_matches "$STANDALONE_NAME" "$OLD_SEMISYNC_RE"
      The status should be failure
    End
    It "does not match merged"
      When call ere_matches "$STANDALONE_NAME" "$MERGED_RE"
      The status should be failure
    End
  End

  Describe "galera CmpD name"
    It "matches only the galera regex"
      When call ere_matches "$GALERA_NAME" "$GALERA_RE"
      The status should be success
    End
    It "does not match standalone"
      When call ere_matches "$GALERA_NAME" "$STANDALONE_RE"
      The status should be failure
    End
    It "does not match old replication"
      When call ere_matches "$GALERA_NAME" "$OLD_REPL_RE"
      The status should be failure
    End
    It "does not match old semisync"
      When call ere_matches "$GALERA_NAME" "$OLD_SEMISYNC_RE"
      The status should be failure
    End
    It "does not match merged"
      When call ere_matches "$GALERA_NAME" "$MERGED_RE"
      The status should be failure
    End
  End

  Describe "old replication CmpD name"
    It "matches the old replication regex"
      When call ere_matches "$OLD_REPL_NAME" "$OLD_REPL_RE"
      The status should be success
    End
    It "does not match standalone"
      When call ere_matches "$OLD_REPL_NAME" "$STANDALONE_RE"
      The status should be failure
    End
    It "does not match galera"
      When call ere_matches "$OLD_REPL_NAME" "$GALERA_RE"
      The status should be failure
    End
    It "does not match old semisync"
      When call ere_matches "$OLD_REPL_NAME" "$OLD_SEMISYNC_RE"
      The status should be failure
    End
    It "does not match merged (the v3.1 contract)"
      When call ere_matches "$OLD_REPL_NAME" "$MERGED_RE"
      The status should be failure
    End
  End

  Describe "old semisync CmpD name"
    It "matches the old semisync regex"
      When call ere_matches "$OLD_SEMISYNC_NAME" "$OLD_SEMISYNC_RE"
      The status should be success
    End
    It "does not match standalone"
      When call ere_matches "$OLD_SEMISYNC_NAME" "$STANDALONE_RE"
      The status should be failure
    End
    It "does not match galera"
      When call ere_matches "$OLD_SEMISYNC_NAME" "$GALERA_RE"
      The status should be failure
    End
    It "does not match old replication"
      When call ere_matches "$OLD_SEMISYNC_NAME" "$OLD_REPL_RE"
      The status should be failure
    End
    It "does not match merged"
      When call ere_matches "$OLD_SEMISYNC_NAME" "$MERGED_RE"
      The status should be failure
    End
  End

  Describe "merged CmpD name (the v3.1 contract)"
    It "matches only the merged regex"
      When call ere_matches "$MERGED_NAME" "$MERGED_RE"
      The status should be success
    End
    It "does not match standalone"
      When call ere_matches "$MERGED_NAME" "$STANDALONE_RE"
      The status should be failure
    End
    It "does not match galera"
      When call ere_matches "$MERGED_NAME" "$GALERA_RE"
      The status should be failure
    End
    It "does not match old replication (the regression Jack flagged)"
      When call ere_matches "$MERGED_NAME" "$OLD_REPL_RE"
      The status should be failure
    End
    It "does not match old semisync"
      When call ere_matches "$MERGED_NAME" "$OLD_SEMISYNC_RE"
      The status should be failure
    End
  End

End
