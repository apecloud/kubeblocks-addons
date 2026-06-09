# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey post-restore Sentinel contract"
  script_file="../dataprotection/post-restore-sentinel.sh"
  restore_example="../../../examples/valkey/restore.yaml"

  It "builds valkey-cli commands as arrays so passwords are not word-split"
    When call grep -E "(_probe_base|data_cli_base|sentinel_cli_base)=\\(" "${script_file}"
    The status should be success
    The stdout should include "_probe_base=("
    The stdout should include "data_cli_base=("
    The stdout should include "sentinel_cli_base=("
  End

  It "does not keep old string command prefixes with interpolated passwords"
    When call grep -E "(data_cli_base|sentinel_cli_base)=\"valkey-cli" "${script_file}"
    The status should be failure
  End

  It "derives sentinel component name from SENTINEL_COMPONENT_NAME when available"
    When call grep -F 'SENTINEL_COMPONENT_NAME:-' "${script_file}"
    The status should be success
    The stdout should include "SENTINEL_COMPONENT_NAME:-"
  End

  It "does not hardcode valkey-sentinel as a fixed component name"
    When call grep -F 'sentinel_comp="${cluster_prefix}-valkey-sentinel"' "${script_file}"
    The status should be failure
  End

  It "fails closed when Sentinel registration configures zero pods"
    When call grep -F "no Sentinel pod was configured" "${script_file}"
    The status should be success
    The stdout should include "no Sentinel pod was configured"
  End

  It "derives clusterDomain from DP_DB_HOST when CLUSTER_DOMAIN is not supplied"
    When call grep -F "svc\\." "${script_file}"
    The status should be success
    The stdout should include "svc\\."
  End

  It "uses current Cluster spec.restore contract in the restore example"
    When call grep -E "restore:|source:|apiGroup: dataprotection.kubeblocks.io|dataprotection.kubeblocks.io/volume-restore-policy: Parallel" "${restore_example}"
    The status should be success
    The stdout should include "restore:"
    The stdout should include "source:"
    The stdout should include "apiGroup: dataprotection.kubeblocks.io"
    The stdout should include "dataprotection.kubeblocks.io/volume-restore-policy: Parallel"
  End

  It "does not use the legacy restore annotation in the restore example"
    When call grep -F "kubeblocks.io/restore-from-backup" "${restore_example}"
    The status should be failure
  End
End
