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

  It "uses SENTINEL_POD_FQDN_LIST as authoritative target set when available"
    When call grep -F 'SENTINEL_POD_FQDN_LIST' "${script_file}"
    The status should be success
    The stdout should include "SENTINEL_POD_FQDN_LIST"
  End

  It "discovers Sentinel targets from headless service DNS when explicit list is missing"
    When call grep -F 'getent hosts "${sentinel_headless}"' "${script_file}"
    The status should be success
    The stdout should include "getent hosts"
  End

  It "requires the chart-expected Sentinel endpoint count from DNS fallback"
    When call grep -F "POST_RESTORE_SENTINEL_EXPECTED_COUNT:-3" "${script_file}"
    The status should be success
    The stdout should include "POST_RESTORE_SENTINEL_EXPECTED_COUNT:-3"
  End

  It "rejects DNS fallback when discovered count differs from expected count"
    When call grep -F 'discovered_sentinel_count}" -ne "${expected_sentinel_count}' "${script_file}"
    The status should be success
    The stdout should include "expected_sentinel_count"
  End

  It "parses SENTINEL_POD_FQDN_LIST into an array with IFS comma split"
    When call grep -E "IFS=',' read -ra sentinel_fqdn_list" "${script_file}"
    The status should be success
    The stdout should include "sentinel_fqdn_list"
  End

  It "exits with error when SENTINEL_POD_FQDN_LIST is set but empty after parsing"
    When call grep -F "SENTINEL_POD_FQDN_LIST is set but empty" "${script_file}"
    The status should be success
    The stdout should include "SENTINEL_POD_FQDN_LIST is set but empty"
  End

  It "fails closed when configured count is less than expected count"
    When call grep -E 'configured.*expected.*Sentinel pods' "${script_file}"
    The status should be success
    The stdout should include "expected Sentinel pods"
  End

  It "does not use ordinal scan fallback for unknown Sentinel targets"
    When call grep -E "POST_RESTORE_SENTINEL_SCAN_LIMIT|sentinel_replica_count|partial probe found" "${script_file}"
    The status should be failure
  End

  It "does not reference restore-sentinel-acl.sh (dead code removed)"
    When call test ! -f "../dataprotection/restore-sentinel-acl.sh"
    The status should be success
  End

  It "guards credentialed sentinel registration behind SENTINEL_PASSWORD"
    When call grep -F 'if [ -n "${SENTINEL_PASSWORD:-}" ]; then' "${script_file}"
    The status should be success
    The stdout should include 'SENTINEL_PASSWORD'
  End

  It "delegates sentinel registration to the self-discovery loop when SENTINEL_PASSWORD is absent"
    When call grep -F "delegated to the Sentinel self-discovery loop" "${script_file}"
    The status should be success
    The stdout should include "self-discovery loop"
  End

  It "never issues sentinel commands on the credential-less path"
    # The no-credential branch must only call verify_replication_converged;
    # any SENTINEL command there would fail with NOAUTH.
    When call grep -F "verify_replication_converged || exit 1" "${script_file}"
    The status should be success
    The stdout should include "verify_replication_converged"
  End
End

Describe "post-restore-sentinel behavioral tests"
  Include ../dataprotection/post-restore-sentinel.sh

  init() {
    convergence_retries=2
    convergence_interval=0
  }
  BeforeAll "init"

  Describe "verify_replication_converged()"
    It "succeeds when the primary is master with all expected replicas attached"
      primary_fqdn="valkey-0.h.ns.svc"
      reachable_data_fqdns=(a b c)
      mock_cli() { printf "role:master\r\nconnected_slaves:2\r\n"; }
      data_cli_base=(mock_cli)
      When call verify_replication_converged
      The status should be success
      The stdout should include "replication converged"
    End

    It "succeeds for a single restored pod with no replicas"
      primary_fqdn="valkey-0.h.ns.svc"
      reachable_data_fqdns=(a)
      mock_cli() { printf "role:master\r\nconnected_slaves:0\r\n"; }
      data_cli_base=(mock_cli)
      When call verify_replication_converged
      The status should be success
      The stdout should include "replication converged"
    End

    It "fails closed when replicas never attach"
      primary_fqdn="valkey-0.h.ns.svc"
      reachable_data_fqdns=(a b c)
      mock_cli() { printf "role:master\r\nconnected_slaves:0\r\n"; }
      data_cli_base=(mock_cli)
      When call verify_replication_converged
      The status should be failure
      The stdout should include "waiting for replication convergence"
      The stderr should include "did not converge"
    End
  End

  Describe "find_primary_fqdn()"
    It "returns the master FQDN and records every reachable data pod"
      comp_prefix="mycluster-valkey"
      comp_headless="mycluster-valkey-headless.ns.svc.cluster.local"
      DATA_REPLICA_COUNT=3
      mock_cli() {
        case "$*" in
          *"mycluster-valkey-1."*ROLE*) echo "master" ;;
          *ROLE*) echo "slave" ;;
        esac
      }
      data_cli_base=(mock_cli)
      _fp_wrapper() {
        find_primary_fqdn && echo "reachable=${#reachable_data_fqdns[@]}"
      }
      When call _fp_wrapper
      The status should be success
      The stdout should include "mycluster-valkey-1.mycluster-valkey-headless.ns.svc.cluster.local"
      The stdout should include "reachable=3"
    End

    It "fails when no pod reports master"
      comp_prefix="mycluster-valkey"
      comp_headless="mycluster-valkey-headless.ns.svc.cluster.local"
      DATA_REPLICA_COUNT=2
      mock_cli() {
        case "$*" in
          *ROLE*) echo "slave" ;;
        esac
      }
      data_cli_base=(mock_cli)
      When call find_primary_fqdn
      The status should be failure
    End
  End
End
