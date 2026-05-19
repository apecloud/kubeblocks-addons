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

    It "declares the replicationMode logical switch as enum (C3 path)"
      # alpha.89 v1 commit 10 (Helen 2026-05-20) — weston 2026-05-20
      # 00:08 msg `cb0afa37` directs that the merged CmpD expose
      # both a single logical `replicationMode` switch AND the four
      # real `rpl_semi_sync_*` variables. The previous C1 path
      # spec asserted absence of `replicationMode`; under C3 the
      # field must exist as an enum `"async" | "semisync"`.
      When call grep_silent 'replicationMode?: "async" | "semisync"' "$(cue_path)"
      The status should be success
    End

    It "binds replicationMode=semisync to the two *_enabled fields = ON via a CUE conditional"
      When call grep_silent 'if replicationMode == "semisync" {' "$(cue_path)"
      The status should be success
    End

    It "binds replicationMode=async to the two *_enabled fields = OFF via a CUE conditional"
      When call grep_silent 'if replicationMode == "async" {' "$(cue_path)"
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
