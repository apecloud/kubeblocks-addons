# shellcheck shell=bash
# shellcheck disable=SC2034

# The files that register a monitor stanza with the Sentinel fleet:
#   - valkey-register-to-sentinel.sh — data-side postProvision (first bootstrap)
#   - post-restore-sentinel.sh       — after a restore, on the target cluster
# valkey-sentinel-start.sh is deliberately NOT part of this contract: it only
# patches its own sentinel conf and leaves the monitor stanza (and its epoch) to
# Valkey, so it never issues SENTINEL monitor.  The scale-out path in
# valkey-sentinel-member-join.sh registers a monitor too, but with its own local
# quorum variable (calculate_sentinel_monitor_quorum → master_quorum), and is
# covered by valkey_sentinel_member_join_spec.sh.
Describe "Valkey Sentinel monitor quorum contract"
  register_script="../scripts/valkey-register-to-sentinel.sh"
  post_restore_script="../dataprotection/post-restore-sentinel.sh"

  It "does not pass a fixed quorum 2 to SENTINEL monitor commands"
    When call bash -c '
      grep -nE "SENTINEL (MONITOR|monitor).* 2($|[[:space:]])" "$@" || true
      grep -nE "\"\\$\\{(primary_port|data_port)\\}\" 2($|[[:space:]])" "$@" || true
    ' -- "${register_script}" "${post_restore_script}"
    The stdout should eq ""
  End

  It "computes monitor quorum as strict majority of the Sentinel target count"
    When call grep -R -nE "sentinel_monitor_quorum=\\$\\(\\( .* / 2 \\+ 1 \\)\\)" \
      "${register_script}" "${post_restore_script}"
    The status should be success
    The stdout should include 'sentinel_monitor_quorum=$(( sentinel_count / 2 + 1 ))'
  End

  It "keeps empty entries from lowering the computed Sentinel count"
    When call grep -R -nF '[ -n "${sentinel_fqdn}" ]' \
      "${register_script}" "${post_restore_script}"
    The status should be success
    The stdout should include '[ -n "${sentinel_fqdn}" ]'
  End

  It "does not compute quorum from an unknown post-restore Sentinel subset"
    When call grep -F 'sentinel_monitor_quorum}" -lt 2' "${post_restore_script}"
    The status should be failure
  End

  It "uses the computed quorum in each SENTINEL monitor path"
    When call grep -R -nF '"${sentinel_monitor_quorum}"' \
      "${register_script}" "${post_restore_script}"
    The status should be success
    The stdout should include "${register_script}"
    The stdout should include "${post_restore_script}"
  End
End
