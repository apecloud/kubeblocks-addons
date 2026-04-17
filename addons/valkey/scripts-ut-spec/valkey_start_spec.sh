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
        The stdout should include "no replicaof directive needed"
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
        The stdout should include "lexicographic"
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
        # Mock valkey-cli: Sentinel returns valkey-0's FQDN
        valkey-cli() {
          echo "valkey-0.valkey-headless.default.svc.cluster.local"$'\n'"6379"
        }
        When call build_replicaof_config
        The status should be success
        The stdout should include "Sentinel reports current master"
        The contents of file "${CONF_RUNTIME}" should include "replicaof valkey-0.valkey-headless.default.svc.cluster.local 6379"
      End
    End
  End
End
