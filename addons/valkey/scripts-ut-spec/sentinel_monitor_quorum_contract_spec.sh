# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey Sentinel monitor quorum contract"
  register_script="../scripts/valkey-register-to-sentinel.sh"
  sentinel_start_script="../scripts/valkey-sentinel-start.sh"
  post_restore_script="../dataprotection/post-restore-sentinel.sh"

  It "does not pass a fixed quorum 2 to SENTINEL monitor commands"
    When call bash -c '
      grep -nE "SENTINEL (MONITOR|monitor).* 2($|[[:space:]])" "$@" || true
      grep -nE "\"\\$\\{(primary_port|data_port)\\}\" 2($|[[:space:]])" "$@" || true
    ' -- "${register_script}" "${sentinel_start_script}" "${post_restore_script}"
    The stdout should eq ""
  End

  It "computes monitor quorum as strict majority of the Sentinel target count"
    When call grep -R -nE "sentinel_monitor_quorum=\\$\\(\\( .* / 2 \\+ 1 \\)\\)" \
      "${register_script}" "${sentinel_start_script}" "${post_restore_script}"
    The status should be success
    The stdout should include 'sentinel_monitor_quorum=$(( sentinel_count / 2 + 1 ))'
  End

  It "keeps empty entries from lowering the computed Sentinel count"
    When call grep -R -nF '[ -n "${sentinel_fqdn}" ]' \
      "${register_script}" "${sentinel_start_script}" "${post_restore_script}"
    The status should be success
    The stdout should include '[ -n "${sentinel_fqdn}" ]'
  End

  It "does not compute quorum from an unknown post-restore Sentinel subset"
    When call grep -F 'sentinel_monitor_quorum}" -lt 2' "${post_restore_script}"
    The status should be failure
  End

  It "uses the computed quorum in each SENTINEL monitor path"
    When call grep -R -nF '"${sentinel_monitor_quorum}"' \
      "${register_script}" "${sentinel_start_script}" "${post_restore_script}"
    The status should be success
    The stdout should include "${register_script}"
    The stdout should include "${sentinel_start_script}"
    The stdout should include "${post_restore_script}"
  End
End
