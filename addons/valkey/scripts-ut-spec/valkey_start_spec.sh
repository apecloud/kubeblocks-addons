# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_start_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Start Bash Script Tests"
  Include $common_library_file
  Include ../scripts/valkey-start.sh

  data_pod_parallel_start_contract() {
    awk '
      /^  podManagementPolicy:/ {
        count++
        if ($2 == "Parallel") parallel++
      }
      END { exit !(count == 1 && parallel == 1) }
    ' ../templates/cmpd.yaml
  }

  init() {
    # Override file paths to local test paths (avoid writing to /etc/valkey or /data)
    CONF_TEMPLATE="./valkey-template.conf"
    CONF_RUNTIME="./valkey.conf"
    ACL_FILE="./users.acl"
    ACL_FILE_BAK="./users.acl.bak"
    ut_mode="true"
    touch "${CONF_TEMPLATE}"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${CONF_TEMPLATE}" "${CONF_RUNTIME}" "${ACL_FILE}" "${ACL_FILE_BAK}" "${common_library_file}"
  }
  AfterAll "cleanup"

  Describe "data pod startup ordering contract"
    It "creates all replication peers in parallel so existing-data startup can discover authority"
      When call data_pod_parallel_start_contract
      The status should be success
    End
  End

  Describe "extract_obj_ordinal()"
    It "extracts ordinal from a StatefulSet pod name"
      When call extract_obj_ordinal "valkey-0"
      The status should be success
      The stdout should eq "0"
    End

    It "extracts ordinal from a longer name"
      When call extract_obj_ordinal "mycluster-valkey-2"
      The status should be success
      The stdout should eq "2"
    End

    It "extracts ordinal from a plain number"
      When call extract_obj_ordinal "5"
      The status should be success
      The stdout should eq "5"
    End
  End

  Describe "rebuild_acl_file()"
    It "removes 'user default' line and preserves other lines"
      printf 'user default on nopass ~* &* +@all\nuser custom on >pass ~* +@all\n' > "${ACL_FILE}"
      When call rebuild_acl_file
      The status should be success
      The contents of file "${ACL_FILE}" should not include "user default on"
      The contents of file "${ACL_FILE}" should include "user custom on"
    End

    It "creates an empty ACL file when it does not exist"
      rm -f "${ACL_FILE}"
      When call rebuild_acl_file
      The status should be success
      The path "${ACL_FILE}" should be exist
    End
  End

  Describe "build_acl_entries()"
    Context "when VALKEY_DEFAULT_PASSWORD is set"
      setup() {
        : > "${CONF_RUNTIME}"
        : > "${ACL_FILE}"
        export VALKEY_DEFAULT_PASSWORD="s3cr3t"
      }
      Before "setup"

      teardown() {
        unset VALKEY_DEFAULT_PASSWORD
      }
      After "teardown"

      It "writes sha256 hash entry and enables protected-mode"
        When call build_acl_entries
        The status should be success
        expected_hash=$(echo -n "s3cr3t" | sha256sum | cut -d' ' -f1)
        The contents of file "${ACL_FILE}" should include "user default on #${expected_hash} ~* &* +@all"
        The contents of file "${CONF_RUNTIME}" should include "protected-mode yes"
      End
    End

    Context "when VALKEY_DEFAULT_PASSWORD is not set"
      setup() {
        : > "${CONF_RUNTIME}"
        : > "${ACL_FILE}"
        unset VALKEY_DEFAULT_PASSWORD
      }
      Before "setup"

      It "writes nopass entry and disables protected-mode"
        When call build_acl_entries
        The status should be success
        The contents of file "${ACL_FILE}" should include "user default on nopass ~* &* +@all"
        The contents of file "${CONF_RUNTIME}" should include "protected-mode no"
      End
    End
  End

  Describe "build_announce_addr()"
    Context "when FQDN is used (no NodePort)"
      setup() {
        : > "${CONF_RUNTIME}"
        unset VALKEY_ADVERTISED_PORT
        unset VALKEY_LB_ADVERTISED_PORT
        export CURRENT_POD_NAME="valkey-0"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      teardown() {
        unset CURRENT_POD_NAME
        unset VALKEY_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After "teardown"

      It "writes replica-announce-ip as the pod FQDN"
        When call build_announce_addr
        The status should be success
        The contents of file "${CONF_RUNTIME}" should include "replica-announce-ip valkey-0.valkey-headless.default.svc.cluster.local"
        The contents of file "${CONF_RUNTIME}" should include "replica-announce-port 6379"
      End
    End

    Context "when NodePort is advertised"
      setup() {
        : > "${CONF_RUNTIME}"
        export VALKEY_ADVERTISED_PORT="valkey-advertised-0:31000,valkey-advertised-1:31001"
        export CURRENT_POD_NAME="valkey-0"
        export CURRENT_POD_HOST_IP="10.0.0.1"
        export SERVICE_PORT="6379"
        unset VALKEY_LB_ADVERTISED_PORT
      }
      Before "setup"

      teardown() {
        unset VALKEY_ADVERTISED_PORT
        unset CURRENT_POD_NAME
        unset CURRENT_POD_HOST_IP
        unset SERVICE_PORT
      }
      After "teardown"

      It "writes the node IP and NodePort as announce address"
        When call build_announce_addr
        The status should be success
        The contents of file "${CONF_RUNTIME}" should include "replica-announce-ip 10.0.0.1"
        The contents of file "${CONF_RUNTIME}" should include "replica-announce-port 31000"
      End
    End

    Context "when FQDN cannot be resolved for current pod"
      setup() {
        : > "${CONF_RUNTIME}"
        unset VALKEY_ADVERTISED_PORT
        unset VALKEY_LB_ADVERTISED_PORT
        export CURRENT_POD_NAME="valkey-99"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      teardown() {
        unset CURRENT_POD_NAME
        unset VALKEY_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After "teardown"

      It "exits with error"
        When run build_announce_addr
        The status should be failure
        The stderr should include "cannot determine FQDN for valkey-99"
      End
    End
  End

  Describe "build_replicaof_config()"
    Context "when this pod is the primary (lexicographic heuristic)"
      setup() {
        : > "${CONF_RUNTIME}"
        unset SENTINEL_COMPONENT_NAME
        unset VALKEY_DEFAULT_PASSWORD
        export CURRENT_POD_NAME="valkey-0"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      teardown() {
        unset CURRENT_POD_NAME
        unset VALKEY_POD_NAME_LIST
        unset VALKEY_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After "teardown"

      It "writes no replicaof directive (this pod is primary)"
        When call build_replicaof_config
        The status should be success
        # build_replicaof_config logs decisions to stderr (info-level), not stdout —
        # stdout is reserved for any captured command output (none in this path).
        The stderr should include "no replicaof directive needed"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof"
      End
    End

    Context "when this pod is a replica"
      setup() {
        : > "${CONF_RUNTIME}"
        unset SENTINEL_COMPONENT_NAME
        unset VALKEY_DEFAULT_PASSWORD
        export CURRENT_POD_NAME="valkey-1"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
      }
      Before "setup"

      teardown() {
        unset CURRENT_POD_NAME
        unset VALKEY_POD_NAME_LIST
        unset VALKEY_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After "teardown"

      It "writes replicaof directive pointing to primary"
        When call build_replicaof_config
        The status should be success
        # Path B (no sentinel) info-logs the lexicographic election to stderr.
        The stderr should include "lexicographic"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-0.valkey-headless.default.svc.cluster.local 6379"
      End
    End

    Context "when Sentinel reports the current master"
      setup() {
        : > "${CONF_RUNTIME}"
        export SENTINEL_COMPONENT_NAME="valkey-sentinel"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.sentinel-headless.default.svc.cluster.local"
        export CURRENT_POD_NAME="valkey-1"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
      }
      Before "setup"

      teardown() {
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset CURRENT_POD_NAME
        unset VALKEY_POD_NAME_LIST
        unset VALKEY_POD_FQDN_LIST
        unset SERVICE_PORT
        unset VALKEY_COMPONENT_NAME
      }
      After "teardown"

      It "uses Sentinel-reported master as replicaof target"
        # Mock query_sentinel_quorum_for_master directly: production code wraps
        # valkey-cli inside `timeout 3 ...` which shell-execs the binary path
        # and bypasses test-scope shell function mocks.
        query_sentinel_quorum_for_master() {
          echo "valkey-0.valkey-headless.default.svc.cluster.local"
        }
        verify_pod_role() {
          echo "master"
        }
        When call build_replicaof_config
        The status should be success
        # Sentinel quorum + role-verified path emits this exact info line to stderr.
        The stderr should include "sentinel quorum + role verified"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-0.valkey-headless.default.svc.cluster.local 6379"
      End
    End

    Context "when Sentinel topology has no trusted master"
      setup() {
        : > "${CONF_RUNTIME}"
        valkey_start_data_dir=$(mktemp -d "${TMPDIR:-/tmp}/valkey-start-data.XXXXXX")
        export DATA_DIR="${valkey_start_data_dir}"
        export SENTINEL_COMPONENT_NAME="valkey-sentinel"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.sentinel-headless.default.svc.cluster.local"
        export CURRENT_POD_NAME="valkey-0"
        export COMPONENT_REPLICAS="2"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local"
        export SERVICE_PORT="6379"
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        get_replica_master_port() { echo "${SERVICE_PORT}"; }
      }
      Before "setup"

      teardown() {
        rm -rf "${valkey_start_data_dir:-}"
        unset DATA_DIR
        unset SENTINEL_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset CURRENT_POD_NAME
        unset COMPONENT_REPLICAS
        unset VALKEY_POD_NAME_LIST
        unset VALKEY_POD_FQDN_LIST
        unset SERVICE_PORT
        unset VALKEY_COMPONENT_NAME
      }
      After "teardown"

      It "allows lexicographic bootstrap for a fresh single-pod data component"
        export COMPONENT_REPLICAS="1"
        export VALKEY_POD_NAME_LIST="valkey-0"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be success
        The stderr should include "electing bootstrap primary"
      End

      It "rejects fresh bootstrap while any configured peer is unreadable"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "peer valkey-1.valkey-headless.default.svc.cluster.local is unreachable"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when one configured peer is unreadable after another validates"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "peer valkey-2.valkey-headless.default.svc.cluster.local is unreachable"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when a peer changes after its local validation"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        peer_one_role_state="${DATA_DIR}/peer-one-role-reads"
        printf '0\n' > "${peer_one_role_state}"
        verify_pod_role() {
          case "$1" in
            valkey-1.*)
              peer_one_role_reads=$(cat "${peer_one_role_state}")
              peer_one_role_reads=$((peer_one_role_reads + 1))
              printf '%s\n' "${peer_one_role_reads}" > "${peer_one_role_state}"
              if [ "${peer_one_role_reads}" -le 2 ]; then
                echo "slave"
              else
                echo "master"
              fi
              ;;
            valkey-2.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "changed role before bootstrap commit"
        The stderr should include "refusing bootstrap"
      End

      It "rejects a truncated FQDN roster before validating peers"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "topology input count mismatch"
        The stderr should include "refusing bootstrap"
      End

      It "rejects duplicate pod names before validating peers"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-0"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "data pod name roster contains duplicate entry valkey-0"
        The stderr should include "refusing bootstrap"
      End

      It "rejects same-count pod name and FQDN rosters that do not map one to one"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "data pod valkey-1 maps to 0 FQDN roster entries"
        The stderr should include "refusing bootstrap"
      End

      It "rejects an FQDN that maps to more than one pod name"
        export CURRENT_POD_NAME="valkey"
        export VALKEY_POD_NAME_LIST="valkey,valkey.0"
        export VALKEY_POD_FQDN_LIST="valkey.0.headless.default.svc.cluster.local,other.headless.default.svc.cluster.local"
        When call validate_parallel_bootstrap_roster
        The status should be failure
        The stderr should include "maps to 2 pod name roster entries"
        The stderr should include "refusing bootstrap"
      End

      It "refuses to guess a primary for existing data without trusted topology"
        touch "${DATA_DIR}/dump.rdb"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "refusing to guess whether this is a full restart or a network partition"
      End

      It "starts an existing-data non-lowest peer on an inert staging upstream when the lowest pod is unreadable"
        touch "${DATA_DIR}/dump.rdb"
        export CURRENT_POD_NAME="valkey-1"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be success
        The stderr should include "starting as a fail-closed staging replica"
        The contents of file "${CONF_RUNTIME}" should include "replicaof 127.0.0.1 1"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof valkey-0.valkey-headless.default.svc.cluster.local"
      End

      It "does not actively replicate existing data when the lowest target is already a replica"
        touch "${DATA_DIR}/dump.rdb"
        export CURRENT_POD_NAME="valkey-1"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-0.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        When call build_replicaof_config
        The status should be success
        The stderr should include "starting as a fail-closed staging replica"
        The contents of file "${CONF_RUNTIME}" should include "replicaof 127.0.0.1 1"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof valkey-0.valkey-headless.default.svc.cluster.local"
      End

      It "rejects an incomplete roster before existing-data replica staging"
        touch "${DATA_DIR}/dump.rdb"
        export CURRENT_POD_NAME="valkey-1"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "topology input count mismatch"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof"
      End

      It "never falls back to a heuristic node already observed as a replica"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo "slave"; }
        follow_slave_to_master() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "is a replica"
        The stderr should include "can prove a current master"
      End

      It "allows the fresh lowest-ordinal pod to bootstrap when every configured peer points to it"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*|valkey-2.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be success
        The stderr should include "parallel cold-start replica view"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof"
      End

      It "repoints a proven-empty inert staging replica only after the full bootstrap validation"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        replica_upstream_state="${DATA_DIR}/replica-upstream"
        printf 'hold\n' > "${replica_upstream_state}"
        get_replica_master_host() {
          if [ "$(cat "${replica_upstream_state}")" = "hold" ]; then
            echo "127.0.0.1"
          else
            echo "valkey-0.valkey-headless.default.svc.cluster.local"
          fi
        }
        get_replica_master_port() {
          if [ "$(cat "${replica_upstream_state}")" = "hold" ]; then
            echo "1"
          else
            echo "6379"
          fi
        }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() {
          [ "$1" = "valkey-1.valkey-headless.default.svc.cluster.local" ] || return 1
          [ "$2" = "valkey-0.valkey-headless.default.svc.cluster.local" ] || return 1
          [ "$3" = "6379" ] || return 1
          printf 'candidate\n' > "${replica_upstream_state}"
        }
        When call build_replicaof_config
        The status should be success
        The stderr should include "repointed inert staging replica"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof"
        The contents of file "${replica_upstream_state}" should eq "candidate"
      End

      It "rejects an inert staging host with the wrong port"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "127.0.0.1"; }
        get_replica_master_port() { echo "2"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "invalid inert staging upstream 127.0.0.1:2"
        The stderr should include "refusing bootstrap"
      End

      It "rejects a bootstrap candidate upstream on the wrong port"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_master_port() { echo "1"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "bootstrap candidate valkey-0.valkey-headless.default.svc.cluster.local on unexpected port 1"
        The stderr should include "refusing bootstrap"
      End

      It "fails closed when an inert staging replica cannot be repointed"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "127.0.0.1"; }
        get_replica_master_port() { echo "1"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        timeout() { return 1; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "cannot repoint staging replica"
        The stderr should include "refusing bootstrap"
        The stderr should not include "parallel cold-start replica view is consistent"
      End

      It "rejects a non-OK REPLICAOF response"
        timeout() {
          echo "ERR wrong target"
          return 0
        }
        When call configure_replica_upstream \
          "valkey-1.valkey-headless.default.svc.cluster.local" \
          "valkey-0.valkey-headless.default.svc.cluster.local" \
          "6379"
        The status should be failure
        The stderr should include "rejected REPLICAOF"
        The stderr should include "refusing bootstrap"
      End

      It "does not repoint a staging replica when Sentinel publishes a late master"
        sentinel_reads="${DATA_DIR}/sentinel-reads"
        configure_calls="${DATA_DIR}/configure-calls"
        printf '0\n' > "${sentinel_reads}"
        printf '0\n' > "${configure_calls}"
        query_sentinel_quorum_for_master() {
          reads=$(cat "${sentinel_reads}")
          reads=$((reads + 1))
          printf '%s\n' "${reads}" > "${sentinel_reads}"
          if [ "${reads}" -gt 6 ]; then
            echo "valkey-1.valkey-headless.default.svc.cluster.local"
          fi
        }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "127.0.0.1"; }
        get_replica_master_port() { echo "1"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() {
          printf '1\n' > "${configure_calls}"
          return 0
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "Sentinel published master"
        The contents of file "${configure_calls}" should eq "0"
      End

      It "does not repoint a staging replica when a direct scan finds a late master"
        scan_reads="${DATA_DIR}/scan-reads"
        configure_calls="${DATA_DIR}/configure-calls"
        printf '0\n' > "${scan_reads}"
        printf '0\n' > "${configure_calls}"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() {
          reads=$(cat "${scan_reads}")
          reads=$((reads + 1))
          printf '%s\n' "${reads}" > "${scan_reads}"
          if [ "${reads}" -gt 3 ]; then
            echo "valkey-1.valkey-headless.default.svc.cluster.local"
          fi
        }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "127.0.0.1"; }
        get_replica_master_port() { echo "1"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() {
          printf '1\n' > "${configure_calls}"
          return 0
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "became master during bootstrap validation"
        The contents of file "${configure_calls}" should eq "0"
      End

      It "converges every peer directly to a Sentinel authority published after staging release"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        sentinel_reads="${DATA_DIR}/sentinel-reads"
        replica_one_state="${DATA_DIR}/replica-one-state"
        replica_two_state="${DATA_DIR}/replica-two-state"
        printf '0\n' > "${sentinel_reads}"
        printf 'hold\n' > "${replica_one_state}"
        printf 'hold\n' > "${replica_two_state}"
        query_sentinel_quorum_for_master() {
          reads=$(cat "${sentinel_reads}")
          reads=$((reads + 1))
          printf '%s\n' "${reads}" > "${sentinel_reads}"
          if [ "${reads}" -gt 7 ]; then
            echo "valkey-2.valkey-headless.default.svc.cluster.local"
          fi
        }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-2.*)
              if [ "$(cat "${sentinel_reads}")" -gt 7 ]; then
                echo "master"
              else
                echo "slave"
              fi
              ;;
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() {
          case "$1" in
            valkey-1.*) state=$(cat "${replica_one_state}") ;;
            valkey-2.*) state=$(cat "${replica_two_state}") ;;
          esac
          case "${state}" in
            hold) echo "127.0.0.1" ;;
            candidate) echo "valkey-0.valkey-headless.default.svc.cluster.local" ;;
            authority) echo "valkey-2.valkey-headless.default.svc.cluster.local" ;;
          esac
        }
        get_replica_master_port() {
          if [ "$(get_replica_master_host "$1")" = "127.0.0.1" ]; then
            echo "1"
          else
            echo "6379"
          fi
        }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() {
          case "$1:$2" in
            valkey-1.*:valkey-0.*) printf 'candidate\n' > "${replica_one_state}" ;;
            valkey-2.*:valkey-0.*) printf 'candidate\n' > "${replica_two_state}" ;;
            valkey-1.*:valkey-2.*) printf 'authority\n' > "${replica_one_state}" ;;
            *) return 1 ;;
          esac
        }
        When call build_replicaof_config
        The status should be success
        The stderr should include "converged partial bootstrap topology"
        The contents of file "${replica_one_state}" should eq "authority"
        The contents of file "${replica_two_state}" should eq "candidate"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-2.valkey-headless.default.svc.cluster.local 6379"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof valkey-0.valkey-headless.default.svc.cluster.local"
      End

      It "retries a partial post-write recovery and removes the cascading topology"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        scan_reads="${DATA_DIR}/scan-reads"
        allow_recovery="${DATA_DIR}/allow-recovery"
        first_residual="${DATA_DIR}/first-residual"
        replica_one_state="${DATA_DIR}/replica-one-state"
        replica_two_state="${DATA_DIR}/replica-two-state"
        printf '0\n' > "${scan_reads}"
        printf 'no\n' > "${allow_recovery}"
        printf 'hold\n' > "${replica_one_state}"
        printf 'hold\n' > "${replica_two_state}"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() {
          reads=$(cat "${scan_reads}")
          reads=$((reads + 1))
          printf '%s\n' "${reads}" > "${scan_reads}"
          if [ "${reads}" -gt 4 ]; then
            echo "valkey-2.valkey-headless.default.svc.cluster.local"
          fi
        }
        verify_pod_role() {
          case "$1" in
            valkey-2.*)
              if [ "$(cat "${scan_reads}")" -gt 4 ]; then
                echo "master"
              else
                echo "slave"
              fi
              ;;
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() {
          case "$1" in
            valkey-1.*) state=$(cat "${replica_one_state}") ;;
            valkey-2.*) state=$(cat "${replica_two_state}") ;;
          esac
          case "${state}" in
            hold) echo "127.0.0.1" ;;
            candidate) echo "valkey-0.valkey-headless.default.svc.cluster.local" ;;
            authority) echo "valkey-2.valkey-headless.default.svc.cluster.local" ;;
          esac
        }
        get_replica_master_port() {
          if [ "$(get_replica_master_host "$1")" = "127.0.0.1" ]; then
            echo "1"
          else
            echo "6379"
          fi
        }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() {
          case "$1:$2" in
            valkey-1.*:valkey-0.*) printf 'candidate\n' > "${replica_one_state}" ;;
            valkey-2.*:valkey-0.*) printf 'candidate\n' > "${replica_two_state}" ;;
            valkey-1.*:valkey-2.*)
              [ "$(cat "${allow_recovery}")" = "yes" ] || return 1
              printf 'authority\n' > "${replica_one_state}"
              ;;
            *) return 1 ;;
          esac
        }
        first_rc=0
        build_replicaof_config >/dev/null 2>"${DATA_DIR}/first-stderr" || first_rc=$?
        if [ "${first_rc}" -ne 0 ] &&
           [ "$(cat "${replica_one_state}")" = "candidate" ] &&
           [ "$(cat "${replica_two_state}")" = "candidate" ]; then
          printf 'candidate,candidate\n' > "${first_residual}"
        fi
        : > "${CONF_RUNTIME}"
        printf 'yes\n' > "${allow_recovery}"
        When call build_replicaof_config
        The status should be success
        The stderr should include "converged partial bootstrap topology"
        The contents of file "${first_residual}" should eq "candidate,candidate"
        The contents of file "${replica_one_state}" should eq "authority"
        The contents of file "${replica_two_state}" should eq "candidate"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-2.valkey-headless.default.svc.cluster.local 6379"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof valkey-0.valkey-headless.default.svc.cluster.local"
      End

      It "forces a pending recovery marker before heuristic bootstrap"
        recovery_marker=$(parallel_bootstrap_recovery_marker)
        configure_calls="${DATA_DIR}/configure-calls"
        printf 'pending\n' > "${recovery_marker}"
        printf '0\n' > "${configure_calls}"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() {
          echo "valkey-0.valkey-headless.default.svc.cluster.local"
        }
        get_replica_master_port() { echo "6379"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() {
          printf '1\n' > "${configure_calls}"
          return 0
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "pending recovery marker requires a unique trusted authority"
        The contents of file "${recovery_marker}" should eq "pending"
        The contents of file "${configure_calls}" should eq "0"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof"
      End

      It "restores the pending marker when authority drifts as recovery is cleared"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        recovery_marker=$(parallel_bootstrap_recovery_marker)
        authority_state="${DATA_DIR}/authority-state"
        replica_one_state="${DATA_DIR}/replica-one-state"
        printf 'stable\n' > "${authority_state}"
        printf 'candidate\n' > "${replica_one_state}"
        query_sentinel_quorum_for_master() {
          echo "valkey-2.valkey-headless.default.svc.cluster.local"
        }
        scan_pods_for_master() {
          echo "valkey-2.valkey-headless.default.svc.cluster.local"
        }
        verify_pod_role() {
          if [ "$(cat "${authority_state}")" = "switched" ]; then
            case "$1" in
              valkey-1.*) echo "master" ;;
              valkey-2.*) echo "slave" ;;
              *) echo "" ;;
            esac
          else
            case "$1" in
              valkey-1.*) echo "slave" ;;
              valkey-2.*) echo "master" ;;
              *) echo "" ;;
            esac
          fi
        }
        get_replica_master_host() {
          case "$1" in
            valkey-1.*)
              if [ "$(cat "${replica_one_state}")" = "candidate" ]; then
                echo "valkey-0.valkey-headless.default.svc.cluster.local"
              else
                echo "valkey-2.valkey-headless.default.svc.cluster.local"
              fi
              ;;
          esac
        }
        get_replica_master_port() { echo "6379"; }
        configure_replica_upstream() {
          [ "$1" = "valkey-1.valkey-headless.default.svc.cluster.local" ] || return 1
          [ "$2" = "valkey-2.valkey-headless.default.svc.cluster.local" ] || return 1
          printf 'authority\n' > "${replica_one_state}"
        }
        rm() {
          if [ "$1" = "-f" ] && [ "$2" = "${recovery_marker}" ]; then
            command rm "$@"
            printf 'switched\n' > "${authority_state}"
            return 0
          fi
          command rm "$@"
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "authority drifted after recovery marker clear"
        The contents of file "${recovery_marker}" should eq "pending"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-2.valkey-headless.default.svc.cluster.local 6379"
      End

      It "converges a peer that still points through a former authority"
        export COMPONENT_REPLICAS="4"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2,valkey-3"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local,valkey-3.valkey-headless.default.svc.cluster.local"
        replica_one_state="${DATA_DIR}/replica-one-state"
        printf 'former-authority\n' > "${replica_one_state}"
        query_sentinel_quorum_for_master() {
          echo "valkey-3.valkey-headless.default.svc.cluster.local"
        }
        scan_pods_for_master() {
          echo "valkey-3.valkey-headless.default.svc.cluster.local"
        }
        verify_pod_role() {
          case "$1" in
            valkey-3.*) echo "master" ;;
            valkey-1.*|valkey-2.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() {
          case "$1" in
            valkey-1.*)
              if [ "$(cat "${replica_one_state}")" = "former-authority" ]; then
                echo "valkey-2.valkey-headless.default.svc.cluster.local"
              else
                echo "valkey-3.valkey-headless.default.svc.cluster.local"
              fi
              ;;
            valkey-2.*) echo "valkey-3.valkey-headless.default.svc.cluster.local" ;;
          esac
        }
        get_replica_master_port() { echo "6379"; }
        configure_replica_upstream() {
          [ "$1" = "valkey-1.valkey-headless.default.svc.cluster.local" ] || return 1
          [ "$2" = "valkey-3.valkey-headless.default.svc.cluster.local" ] || return 1
          [ "$3" = "6379" ] || return 1
          printf 'authority\n' > "${replica_one_state}"
        }
        When call build_replicaof_config
        The status should be success
        The stderr should include "converged partial bootstrap topology"
        The contents of file "${replica_one_state}" should eq "authority"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-3.valkey-headless.default.svc.cluster.local 6379"
      End

      It "validates the complete recovery plan before mutating any peer"
        export COMPONENT_REPLICAS="4"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2,valkey-3"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local,valkey-3.valkey-headless.default.svc.cluster.local"
        replica_one_state="${DATA_DIR}/replica-one-state"
        printf 'candidate\n' > "${replica_one_state}"
        query_sentinel_quorum_for_master() {
          echo "valkey-3.valkey-headless.default.svc.cluster.local"
        }
        scan_pods_for_master() {
          echo "valkey-3.valkey-headless.default.svc.cluster.local"
        }
        verify_pod_role() {
          case "$1" in
            valkey-3.*) echo "master" ;;
            valkey-1.*|valkey-2.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() {
          case "$1" in
            valkey-1.*)
              if [ "$(cat "${replica_one_state}")" = "candidate" ]; then
                echo "valkey-0.valkey-headless.default.svc.cluster.local"
              else
                echo "valkey-3.valkey-headless.default.svc.cluster.local"
              fi
              ;;
            valkey-2.*) echo "outside.example.invalid" ;;
          esac
        }
        get_replica_master_port() { echo "6379"; }
        configure_replica_upstream() {
          [ "$1" = "valkey-1.valkey-headless.default.svc.cluster.local" ] || return 1
          [ "$2" = "valkey-3.valkey-headless.default.svc.cluster.local" ] || return 1
          printf 'authority\n' > "${replica_one_state}"
        }
        first_rc=0
        build_replicaof_config >/dev/null 2>"${DATA_DIR}/first-stderr" || first_rc=$?
        printf '%s\n' "${first_rc}" > "${DATA_DIR}/first-rc"
        : > "${CONF_RUNTIME}"
        When call build_replicaof_config
        The status should be failure
        The stderr should include "outside an unambiguous data-pod roster"
        The contents of file "${DATA_DIR}/first-rc" should not eq "0"
        The contents of file "${replica_one_state}" should eq "candidate"
        The contents of file "${CONF_RUNTIME}" should not include "replicaof"
      End

      It "rejects bootstrap when a successful repoint still leaves the peer on hold"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "127.0.0.1"; }
        get_replica_master_port() { echo "1"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        configure_replica_upstream() { return 0; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "remained on inert staging upstream"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when an observed replica still has keys in any database"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() {
          printf '# Keyspace\r\ndb2:keys=30,expires=0,avg_ttl=0\r\n'
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "retains 30 key(s) in db2"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when a zero-key replica retains a persisted Function library"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() {
          printf 'library_name\nsurviving-lib\nengine\nLUA\n'
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "retains persisted Function state"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when replica Function evidence is unreadable"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { return 1; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "Function evidence is unreadable"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when a peer gains keys before the final commit boundary"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        peer_keyspace_state="${DATA_DIR}/peer-keyspace-reads"
        printf '0\n' > "${peer_keyspace_state}"
        get_replica_keyspace_info() {
          peer_keyspace_reads=$(cat "${peer_keyspace_state}")
          peer_keyspace_reads=$((peer_keyspace_reads + 1))
          printf '%s\n' "${peer_keyspace_reads}" > "${peer_keyspace_state}"
          if [ "${peer_keyspace_reads}" -eq 1 ]; then
            printf '# Keyspace\r\n'
          else
            printf '# Keyspace\r\ndb0:keys=1,expires=0,avg_ttl=0\r\n'
          fi
        }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "retains 1 key(s) in db0"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when a peer gains Function state before the final commit boundary"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        peer_function_state="${DATA_DIR}/peer-function-reads"
        printf '0\n' > "${peer_function_state}"
        get_replica_function_list() {
          peer_function_reads=$(cat "${peer_function_state}")
          peer_function_reads=$((peer_function_reads + 1))
          printf '%s\n' "${peer_function_reads}" > "${peer_function_state}"
          if [ "${peer_function_reads}" -gt 1 ]; then
            printf 'library_name\nlate-lib\nengine\nLUA\n'
          fi
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "retains persisted Function state"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when replica keyspace evidence is unreadable"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { return 1; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "keyspace evidence is unreadable"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when replica keyspace evidence is malformed"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf 'ERR invalid response\n'; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "keyspace evidence is malformed"
        The stderr should include "refusing bootstrap"
      End

      It "rejects fresh bootstrap when a replica changes role during validation"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        peer_role_state="${DATA_DIR}/peer-role-reads"
        printf '0\n' > "${peer_role_state}"
        verify_pod_role() {
          case "$1" in
            valkey-1.*)
              peer_role_reads=$(cat "${peer_role_state}")
              peer_role_reads=$((peer_role_reads + 1))
              printf '%s\n' "${peer_role_reads}" > "${peer_role_state}"
              if [ "${peer_role_reads}" -eq 1 ]; then
                echo "slave"
              else
                echo "master"
              fi
              ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "valkey-0.valkey-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "changed role during bootstrap validation"
        The stderr should include "refusing bootstrap"
      End

      It "fails closed when any peer is already a slave even if this pod data dir has existing data"
        touch "${DATA_DIR}/dump.rdb"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "contains existing data"
        The stderr should include "refusing to guess whether this is a full restart or a network partition"
      End

      It "rejects a fresh bootstrap replica whose upstream is outside the data pod roster"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() { echo "retired-valkey-9.other-headless.default.svc.cluster.local"; }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "outside an unambiguous data-pod roster"
        The stderr should include "refusing bootstrap"
      End

      It "rejects an ambiguous data pod roster before fresh bootstrap"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-0.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "data pod FQDN roster contains duplicate entry"
        The stderr should include "refusing bootstrap"
      End

      It "rejects conflicting replica upstream targets during fresh bootstrap"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() {
          case "$1" in
            valkey-1.*|valkey-2.*) echo "slave" ;;
            *) echo "" ;;
          esac
        }
        get_replica_master_host() {
          case "$1" in
            valkey-1.*) echo "valkey-0.valkey-headless.default.svc.cluster.local" ;;
            valkey-2.*) echo "valkey-2.valkey-headless.default.svc.cluster.local" ;;
          esac
        }
        get_replica_keyspace_info() { printf '# Keyspace\r\n'; }
        get_replica_function_list() { :; }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "refusing conflicting replica targets"
      End

      It "never lets a non-lowest ordinal pod self-bootstrap"
        export CURRENT_POD_NAME="valkey-1"
        export COMPONENT_REPLICAS="3"
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.valkey-headless.default.svc.cluster.local,valkey-1.valkey-headless.default.svc.cluster.local,valkey-2.valkey-headless.default.svc.cluster.local"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() { echo ""; }
        verify_pod_role() { echo ""; }
        When call build_replicaof_config
        The status should be success
        The stderr should include "electing bootstrap primary by lexicographic order"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-0.valkey-headless.default.svc.cluster.local 6379"
      End

      It "does not use the cold-start fallback when Sentinel already proves a master"
        query_sentinel_quorum_for_master() {
          echo "valkey-1.valkey-headless.default.svc.cluster.local"
        }
        verify_pod_role() { echo "master"; }
        validate_parallel_bootstrap_replica_view() {
          echo "unexpected cold-start fallback" >&2
          return 1
        }
        When call build_replicaof_config
        The status should be success
        The stderr should not include "unexpected cold-start fallback"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-1.valkey-headless.default.svc.cluster.local 6379"
      End

      It "fails closed instead of falling through when the peer master view is ambiguous"
        query_sentinel_quorum_for_master() { echo ""; }
        scan_pods_for_master() {
          echo "ERROR: multiple data pods report role:master" >&2
          return 1
        }
        When call build_replicaof_config
        The status should be failure
        The stderr should include "ambiguous master view"
        The stderr should not include "electing bootstrap primary"
      End
    End
  End

  Describe "scan_pods_for_master()"
    scan_env() {
      export CURRENT_POD_NAME="valkey-0"
      export VALKEY_POD_FQDN_LIST="valkey-0.h,valkey-1.h,valkey-2.h"
      export SERVICE_PORT="6379"
    }
    Before "scan_env"

    timeout() {
      shift
      "$@"
    }

    It "returns the only peer that positively reports master"
      valkey-cli() {
        case "$*" in
          *"-h valkey-1.h "*) printf 'role:master\n' ;;
          *) printf 'role:slave\n' ;;
        esac
      }
      When call scan_pods_for_master
      The status should be success
      The stdout should equal "valkey-1.h"
    End

    It "rejects two peers that both report master"
      valkey-cli() { printf 'role:master\n'; }
      When call scan_pods_for_master
      The status should be failure
      The stderr should include "multiple data pods report role:master"
    End
  End
End
