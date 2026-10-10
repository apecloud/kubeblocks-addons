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
    When call grep -E "restore:|source:|apiGroup: dataprotection.kubeblocks.io|dataprotection.kubeblocks.io/volume-restore-policy: Parallel|DATA_REPLICA_COUNT" "${restore_example}"
    The status should be success
    The stdout should include "restore:"
    The stdout should include "source:"
    The stdout should include "apiGroup: dataprotection.kubeblocks.io"
    The stdout should include "dataprotection.kubeblocks.io/volume-restore-policy: Parallel"
    The stdout should include "DATA_REPLICA_COUNT"
  End

  It "does not use the legacy restore annotation in the restore example"
    When call grep -F "kubeblocks.io/restore-from-backup" "${restore_example}"
    The status should be failure
  End

  It "uses EnvVar array format (not object) for restore-env annotation"
    When call grep -F '"name":"DATA_REPLICA_COUNT","value"' "${restore_example}"
    The status should be success
    The stdout should include '"name":"DATA_REPLICA_COUNT"'
  End

  It "documents POST_RESTORE_SENTINEL_EXPECTED_COUNT in the restore example"
    When call grep -F 'POST_RESTORE_SENTINEL_EXPECTED_COUNT' "${restore_example}"
    The status should be success
    The stdout should include "POST_RESTORE_SENTINEL_EXPECTED_COUNT"
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

  It "accepts DNS-discovered Sentinel count as authoritative when env var is unset"
    When call grep -F 'expected_sentinel_count="${discovered_sentinel_count}"' "${script_file}"
    The status should be success
    The stdout should include "expected_sentinel_count"
  End

  It "enforces count match only when POST_RESTORE_SENTINEL_EXPECTED_COUNT is explicitly set"
    When call grep -F 'POST_RESTORE_SENTINEL_EXPECTED_COUNT:-' "${script_file}"
    The status should be success
    The stdout should include "POST_RESTORE_SENTINEL_EXPECTED_COUNT"
  End

  It "rejects DNS fallback when explicitly-set expected count differs from discovered"
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
    When call grep -F "verify_replication_converged" "${script_file}"
    The status should be success
    The stdout should include "verify_replication_converged"
  End

  It "always verifies data replication after optional Sentinel registration"
    final_convergence_gate() {
      tail -n 20 "${script_file}" | grep -F "verify_replication_converged"
    }
    When call final_convergence_gate
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

  Describe "build_sentinel_target_list()"
    It "rejects duplicate explicit Sentinel targets"
      SENTINEL_POD_FQDN_LIST="s0.h.ns.svc,s0.h.ns.svc,s1.h.ns.svc"
      When call build_sentinel_target_list
      The status should be failure
      The stderr should include "duplicate target"
    End

    It "rejects empty explicit Sentinel targets"
      SENTINEL_POD_FQDN_LIST="s0.h.ns.svc,,s1.h.ns.svc"
      When call build_sentinel_target_list
      The status should be failure
      The stderr should include "empty target"
    End
  End

  Describe "register_sentinels_with_credentials()"
    It "replaces a stale same-name monitor and verifies the new endpoint"
      sentinel_fqdn_list=(s0.h.ns.svc)
      expected_sentinel_count=1
      primary_fqdn="valkey-0.h.ns.svc"
      data_port=6379
      master_name="cluster-valkey"
      DP_DB_PASSWORD=""
      sentinel_calls=$(mktemp)
      sentinel_reads=$(mktemp)
      printf '0\n' > "${sentinel_reads}"
      getent() { printf '10.0.0.10 %s\n' "$2"; }
      mock_sentinel_cli() {
        printf '%s\n' "$*" >> "${sentinel_calls}"
        case "$*" in
          *PING*) echo PONG ;;
          *get-master-addr-by-name*)
            count=$(cat "${sentinel_reads}")
            count=$((count + 1))
            printf '%s\n' "${count}" > "${sentinel_reads}"
            if [ "${count}" -eq 1 ]; then
              printf '10.0.0.99\n6379\n'
            else
              printf '10.0.0.10\n6379\n'
            fi
            ;;
          *) echo OK ;;
        esac
      }
      sentinel_cli_base=(mock_sentinel_cli)
      _replace_wrapper() {
        register_sentinels_with_credentials
        rc=$?
        grep -F "SENTINEL remove cluster-valkey" "${sentinel_calls}"
        grep -F "SENTINEL monitor cluster-valkey valkey-0.h.ns.svc 6379 1" "${sentinel_calls}"
        rm -f "${sentinel_calls}" "${sentinel_reads}"
        return "${rc}"
      }
      When call _replace_wrapper
      The status should be success
      The stdout should include "SENTINEL remove"
      The stdout should include "SENTINEL monitor"
    End
  End

  Describe "post_restore_main()"
    It "does not let credentialed Sentinel registration waive data convergence"
      SENTINEL_PASSWORD="sentinel-secret"
      detect_tls_args() { _tls_args=(); }
      derive_target_context() { return 0; }
      discover_primary() {
        primary_fqdn="valkey-0.h.ns.svc"
        reachable_data_fqdns=(a b c)
        return 0
      }
      build_sentinel_target_list() { return 0; }
      register_sentinels_with_credentials() { echo "registration-ok"; }
      verify_replication_converged() {
        echo "convergence-failed" >&2
        return 1
      }
      When call post_restore_main
      The status should be failure
      The stdout should include "registration-ok"
      The stderr should include "convergence-failed"
    End
  End

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

    It "does not let a partial primary-only discovery become a zero-replica success"
      primary_fqdn="valkey-0.h.ns.svc"
      DATA_REPLICA_COUNT=3
      reachable_data_fqdns=(a)
      mock_cli() { printf "role:master\r\nconnected_slaves:0\r\n"; }
      data_cli_base=(mock_cli)
      When call verify_replication_converged
      The status should be failure
      The stdout should include "connected_slaves=0/2"
      The stderr should include "did not converge"
    End

    It "requires an explicit expected data count for credential-less HA restores"
      primary_fqdn="valkey-0.h.ns.svc"
      sentinel_headless="s-headless.ns.svc.cluster.local"
      unset DATA_REPLICA_COUNT
      unset POST_RESTORE_DATA_EXPECTED_COUNT
      reachable_data_fqdns=(a)
      mock_cli() { printf "role:master\r\nconnected_slaves:0\r\n"; }
      data_cli_base=(mock_cli)
      _vrc_with_sentinel_dns() {
        getent() {
          [ "$1" = "hosts" ] && printf "10.0.0.1 %s\n" "$2"
        }
        verify_replication_converged
      }
      When call _vrc_with_sentinel_dns
      The status should be failure
      The stderr should include "DATA_REPLICA_COUNT"
      The stderr should include "partial data scan"
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
