# shellcheck shell=bash
# Contract: wal_init_zero must be a PURE STRING enum in CUE.
# A bool|string disjunction is classified BoolType by the KubeBlocks CUE
# visitor (BoolKind is checked before StringKind in IncompleteKind bitmask
# order), which routes values through strconv.ParseBool and rejects
# PostgreSQL's canonical on/off spelling — including the tpl default
# `wal_init_zero = off`, which would then fail whole-rendered-file
# validation on cluster creation and every reconfigure.

Describe "PostgreSQL wal_init_zero configuration"
  assert_wal_init_zero_contract() {
    local major="$1"
    local cue="../config/pg${major}-config-constraint.cue"

    # exact expected type: string enum accepting both PG and bool spellings
    grep -Fq 'wal_init_zero?: string & "on" | "off" | "true" | "false"' "${cue}"
    # guard against regression to any bool-kind participation for this GUC
    if grep -E 'wal_init_zero\?:.*bool' "${cue}"; then
      echo "wal_init_zero must not include a bool branch (BoolKind wins kind classification and breaks on/off)" >&2
      return 1
    fi
    # the tpl default uses PG spelling and must be inside the accepted enum
    grep -Fq 'wal_init_zero = off' "../config/pg${major}-config.tpl"
  }

  It "keeps pg12 wal_init_zero a string enum accepting on/off/true/false"
    When call assert_wal_init_zero_contract 12
    The status should be success
  End

  It "keeps pg14 wal_init_zero a string enum accepting on/off/true/false"
    When call assert_wal_init_zero_contract 14
    The status should be success
  End

  It "keeps pg15 wal_init_zero a string enum accepting on/off/true/false"
    When call assert_wal_init_zero_contract 15
    The status should be success
  End

  It "keeps pg16 wal_init_zero a string enum accepting on/off/true/false"
    When call assert_wal_init_zero_contract 16
    The status should be success
  End

  It "keeps pg17 wal_init_zero a string enum accepting on/off/true/false"
    When call assert_wal_init_zero_contract 17
    The status should be success
  End

  It "keeps pg18 wal_init_zero a string enum accepting on/off/true/false"
    When call assert_wal_init_zero_contract 18
    The status should be success
  End
End
