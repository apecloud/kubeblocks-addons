# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey config template defaults contract"
  config_tpl="../config/valkey-config.tpl"

  It "keeps maxmemory-policy at the Valkey upstream default (noeviction)"
    # Database-safe default: writes fail loudly at maxmemory instead of
    # silently evicting data (issue #3015). Cache profiles override via
    # the dynamic parameter.
    When call grep -E '^maxmemory-policy noeviction$' "${config_tpl}"
    The status should be success
    The stdout should include "noeviction"
  End

  It "does not silently default to an eviction policy"
    When call grep -E '^maxmemory-policy (volatile|allkeys)' "${config_tpl}"
    The status should be failure
  End
End
