# shellcheck shell=sh

# Lock the alpha.89 v1 commit 3 (C1 path) contract that the merged
# CmpD's PD declares a CUE schema for the four semisync engine
# variables, and that those variables are also classified as
# dynamic so the KB Configure controller does not fall back to
# rolling restart on reconfigure. Jack design review (15:50)
# Class 4 sentinel: invalid values must be rejected at the
# controller parameter reconcile path, which requires the CUE
# schema to actually declare them.

Describe "alpha.89 merged PD CUE schema + dynamic classification"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  cue_path() {
    printf "%s/addons/mariadb/config/mariadb-config-constraint.cue" "$(repo_root)"
  }

  paramsdef_path() {
    printf "%s/addons/mariadb/templates/paramsdef.yaml" "$(repo_root)"
  }

  effect_scope_path() {
    printf "%s/addons/mariadb/config/mariadb-config-effect-scope.yaml" "$(repo_root)"
  }

  # Silent grep that returns only an exit status; avoids
  # stdout-eats-expectation warnings under shellspec When call.
  grep_silent() {
    grep -qF -- "$1" "$2"
  }

  # Awk-based search for a literal line of YAML (whitespace plus
  # a list-style "- name" entry) inside the rendered text. Prints
  # "ok" on a hit so the spec can compare with The output equals.
  awk_line_in_block() {
    awk -v block_start_re="$1" -v hit_re="$2" '
      $0 ~ block_start_re { in_block=1; next }
      in_block && /^---[[:space:]]*$/ { in_block=0; next }
      in_block && $0 ~ hit_re { print "ok"; exit }
    ' "$3"
  }

  awk_in_dyn_params() {
    awk -v hit_re="$1" '
      /^dynamicParameters:[[:space:]]*$/ { in_dyn=1; next }
      in_dyn && /^[A-Za-z]/ { in_dyn=0 }
      in_dyn && $0 ~ hit_re { print "ok"; exit }
    ' "$2"
  }

  Describe "CUE constraint file"
    It "exists at the expected path"
      When call test -f "$(cue_path)"
      The status should be success
    End

    It "declares the MariaDBParameter top-level key"
      When call grep_silent "#MariaDBParameter:" "$(cue_path)"
      The status should be success
    End

    It "constrains rpl_semi_sync_master_enabled to an ON/OFF enum"
      When call grep_silent 'rpl_semi_sync_master_enabled?: string & "ON" | "OFF"' "$(cue_path)"
      The status should be success
    End

    It "constrains rpl_semi_sync_slave_enabled to an ON/OFF enum"
      When call grep_silent 'rpl_semi_sync_slave_enabled?: string & "ON" | "OFF"' "$(cue_path)"
      The status should be success
    End

    It "constrains rpl_semi_sync_master_wait_for_slave_count to a positive int range"
      When call grep_silent 'rpl_semi_sync_master_wait_for_slave_count?: int & >=1 & <=65535' "$(cue_path)"
      The status should be success
    End

    It "constrains rpl_semi_sync_master_timeout to a positive int range"
      When call grep_silent 'rpl_semi_sync_master_timeout?: int & >=1 & <=2147483647' "$(cue_path)"
      The status should be success
    End

    It "does not declare a replicationMode CUE field (C3 mapper owns it, not CUE)"
      # alpha.89 v1 commit 11 (Helen 2026-05-20, post Jack
      # KB-validator behavioral test msg `ea50aa12`) — KB does not
      # emit CUE-derived field values into the rendered my.cnf, so
      # a `replicationMode` field in CUE would either be silently
      # ignored OR land verbatim in my.cnf (which mariadbd rejects
      # as an unknown variable). C3's `replicationMode` lives as a
      # ComponentSpec parameter consumed by an addon-side mapper
      # in reconfigureAction BEFORE my.cnf render; CUE only
      # validates the four real engine variables. This negative
      # assertion guards against a future edit silently
      # reintroducing `replicationMode` into CUE.
      When call grep -qE '^[[:space:]]*replicationMode\??:' "$(cue_path)"
      The status should be failure
    End

    It "does not declare any if replicationMode CUE conditional block as code"
      # Same post-Jack-finding reason: CUE conditional blocks would
      # only validate, not derive; expressing C3 precedence in CUE
      # gives a false sense of completeness. The grep below
      # excludes comment lines (those starting with `//`) so the
      # commit 11 preamble's textual reference to the removed
      # blocks does not trigger a false positive.
      When call grep -qE '^[[:space:]]*if[[:space:]]+replicationMode' "$(cue_path)"
      The status should be failure
    End

    It "opens the #MariaDBParameter struct so base my.cnf keys pass through"
      # alpha.89 v1 commit 11 (Helen 2026-05-20) — retroactive fix
      # for commit 3 v2 closed-section bug surfaced by Jack's
      # KB-validator full-base-merge test (msg `ea50aa12`). Without
      # the `[string]: _` open marker inside #MariaDBParameter,
      # ValidateConfigWithCue() rejects base my.cnf keys
      # (binlog_format, max_connections, slow_query_log, etc.)
      # that this schema does not enumerate.
      When call grep_silent "[string]: _" "$(cue_path)"
      The status should be success
    End

    It "explicitly forbids the synthetic replicationmode key in my.cnf"
      # alpha.89 v1 commit 11 v2 (Helen 2026-05-20, Jack B1 fix
      # msg `f8e7e078`) — the `[string]: _` open marker alone
      # allowed a `replicationMode=semisync` patch to merge into
      # my.cnf (KB's INI parser lowercases it to `replicationmode`,
      # which mariadbd does not recognize as a server variable).
      # The C3 design places `replicationMode` at the
      # ComponentSpec-parameter layer consumed by an addon mapper
      # BEFORE my.cnf render; under no path should the key appear
      # in my.cnf. The `_|_` (CUE bottom) declaration forbids the
      # specific lowercase key, while the open `[string]: _`
      # pattern still permits unrelated base my.cnf keys.
      When call grep_silent "replicationmode?: _|_" "$(cue_path)"
      The status should be success
    End

    # Jack design review (2026-05-19 18:48 Class 4 blocker B1) —
    # without an INI section binding, KB's `ValidateConfigWithCue()`
    # does not use the top-level definition. The constraints become
    # unreferenced and invalid values (e.g. `MAYBE` for an enum,
    # `0` for a positive-int range) silently pass the validator,
    # defeating fail-closed. Lock the binding's presence so a future
    # edit cannot regress it without surfacing here.
    It "binds #MariaDBParameter to every INI section via [SectionName=_]"
      When call grep_silent "[SectionName=_]: #MariaDBParameter" "$(cue_path)"
      The status should be success
    End
  End

  Describe "merged PD parametersSchema wiring"
    It "the merged PD block declares parametersSchema with the CUE top-level key"
      When call awk_line_in_block \
        'name:[[:space:]]+mariadb-replication-merged-pd[[:space:]]*$' \
        'topLevelKey:[[:space:]]+MariaDBParameter' \
        "$(paramsdef_path)"
      The output should equal "ok"
    End

    It "the merged PD block references the CUE file via Files.Get"
      When call awk_line_in_block \
        'name:[[:space:]]+mariadb-replication-merged-pd[[:space:]]*$' \
        'Files\.Get "config/mariadb-config-constraint\.cue"' \
        "$(paramsdef_path)"
      The output should equal "ok"
    End
  End

  Describe "dynamicParameters classification"
    It "lists rpl_semi_sync_master_enabled in dynamicParameters"
      When call awk_in_dyn_params \
        '^[[:space:]]+-[[:space:]]+rpl_semi_sync_master_enabled[[:space:]]*$' \
        "$(effect_scope_path)"
      The output should equal "ok"
    End

    It "lists rpl_semi_sync_slave_enabled in dynamicParameters"
      When call awk_in_dyn_params \
        '^[[:space:]]+-[[:space:]]+rpl_semi_sync_slave_enabled[[:space:]]*$' \
        "$(effect_scope_path)"
      The output should equal "ok"
    End

    It "lists rpl_semi_sync_master_wait_for_slave_count in dynamicParameters"
      When call awk_in_dyn_params \
        '^[[:space:]]+-[[:space:]]+rpl_semi_sync_master_wait_for_slave_count[[:space:]]*$' \
        "$(effect_scope_path)"
      The output should equal "ok"
    End

    It "lists rpl_semi_sync_master_timeout in dynamicParameters"
      When call awk_in_dyn_params \
        '^[[:space:]]+-[[:space:]]+rpl_semi_sync_master_timeout[[:space:]]*$' \
        "$(effect_scope_path)"
      The output should equal "ok"
    End
  End

End
