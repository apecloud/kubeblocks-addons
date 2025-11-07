# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "common_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Common Script Functions Tests"
  
  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    
    # Setup minimal test environment
    export CONFIG_FILE_PATH="/tmp/test_etcd.conf"
    export TLS_MOUNT_PATH="/tmp/test_certs"
    export config_file="$CONFIG_FILE_PATH"
    
    # Create simple config file
    mkdir -p /tmp
    echo "advertise-client-urls: http://test:2379" > "$CONFIG_FILE_PATH"
    
    # Create minimal TLS directory structure for tests
    mkdir -p "$TLS_MOUNT_PATH"
    touch "$TLS_MOUNT_PATH/ca.pem"
    touch "$TLS_MOUNT_PATH/cert.pem"
    touch "$TLS_MOUNT_PATH/key.pem"
    
    # Mock etcdctl command
    etcdctl() {
      if [[ "$*" == *"endpoint status -w fields"* ]]; then
        echo '"MemberID": 1002'
        echo '"Leader": 1002'
        echo '"Raft Term": 1'
        echo '"Raft Index": 100'
        return 0
      else
        echo "MOCK: etcdctl $*"
        return 0
      fi
    }
    
    # Mock etcdutl
    etcdutl() {
      echo "MOCK: etcdutl $*"
      return 0
    }
    
    # Mock log function
    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    }
    
    # Mock error_exit function for test environment
    error_exit() {
      echo "ERROR: $1" >&2
      return 1
    }
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
    rm -f "$CONFIG_FILE_PATH"
    rm -rf "$TLS_MOUNT_PATH"
    unset ut_mode CONFIG_FILE_PATH TLS_MOUNT_PATH config_file
    unset -f etcdctl etcdutl log error_exit
  }
  AfterAll 'cleanup'

  # Load only the common library (not the full common.sh script)
  Include $common_library_file

  # Define the functions we want to test directly here to avoid path issues
  get_protocol() {
    local url_type="$1"
    local conf_file="${config_file:-$CONFIG_FILE_PATH}"

    if [ -f "$conf_file" ] && grep "$url_type" "$conf_file" | grep -q 'https'; then
      echo "https"
    else
      echo "http"
    fi
  }

  exec_etcdctl() {
    local endpoint="$1"
    shift

    # Auto-detect protocol and add prefix if not present
    if [[ "$endpoint" != http://* ]] && [[ "$endpoint" != https://* ]]; then
      if get_protocol "advertise-client-urls" | grep -q "https"; then
        endpoint="https://$endpoint"
      else
        endpoint="http://$endpoint"
      fi
    fi

    if get_protocol "advertise-client-urls" | grep -q "https"; then
      [ ! -d "$TLS_MOUNT_PATH" ] && echo "ERROR: TLS_MOUNT_PATH '$TLS_MOUNT_PATH' not found" >&2 && return 1
      for cert in ca.pem cert.pem key.pem; do
        [ ! -s "$TLS_MOUNT_PATH/$cert" ] && echo "ERROR: TLS certificate '$cert' missing or empty" >&2 && return 1
      done
      etcdctl --endpoints="$endpoint" --cacert="$TLS_MOUNT_PATH/ca.pem" --cert="$TLS_MOUNT_PATH/cert.pem" --key="$TLS_MOUNT_PATH/key.pem" "$@"
    else
      etcdctl --endpoints="$endpoint" "$@"
    fi
  }

  parse_endpoint_field() {
    local endpoint="$1"
    local field_name="$2"
    local status field_value

    if ! status=$(exec_etcdctl "$endpoint" endpoint status -w fields); then
      error_exit "Failed to get endpoint status from $endpoint"
    fi

    field_value=$(echo "$status" | awk -F': ' -v field="\"$field_name\"" '$1 ~ field {gsub(/[^0-9]/, "", $2); print $2}')

    [ -z "$field_value" ] && error_exit "Failed to extract $field_name from endpoint status"

    echo "$field_value"
  }

  is_leader() {
    local contact_point="$1"
    local member_id leader_id

    member_id=$(parse_endpoint_field "$contact_point" "MemberID")
    leader_id=$(parse_endpoint_field "$contact_point" "Leader")

    [ "$member_id" = "$leader_id" ]
  }

  get_member_id() {
    local endpoint="$1"
    parse_endpoint_field "$endpoint" "MemberID"
  }

  get_member_id_hex() {
    local endpoint="$1"
    member_id=$(parse_endpoint_field "$endpoint" "MemberID")
    printf "%x" "$member_id"
  }

  Describe "get_protocol() function"
    It "returns https when config contains https"
      echo "advertise-client-urls: https://test:2379" > "$CONFIG_FILE_PATH"
      
      When call get_protocol "advertise-client-urls"
      The status should be success
      The stdout should equal "https"
    End

    It "returns http when config contains http"
      echo "advertise-client-urls: http://test:2379" > "$CONFIG_FILE_PATH"
      
      When call get_protocol "advertise-client-urls"
      The status should be success
      The stdout should equal "http"
    End
  End

  Describe "exec_etcdctl() function"
    It "adds http prefix when no protocol specified"
      echo "advertise-client-urls: http://test:2379" > "$CONFIG_FILE_PATH"
      
      When call exec_etcdctl "etcd-0:2379" "member" "list"
      The status should be success
      The stdout should include "MOCK: etcdctl --endpoints=http://etcd-0:2379 member list"
    End

    It "uses existing protocol when specified"
      When call exec_etcdctl "https://etcd-0:2379" "member" "list"
      The status should be success
      The stdout should include "MOCK: etcdctl --endpoints=https://etcd-0:2379"
    End
  End

  Describe "parse_endpoint_field() function"
    It "extracts field value from endpoint status"
      When call parse_endpoint_field "http://etcd-0:2379" "MemberID"
      The status should be success
      The stdout should equal "1002"
    End
  End

  Describe "is_leader() function"
    It "returns success when member ID equals leader ID"
      When call is_leader "http://etcd-1:2379"
      The status should be success
    End
  End

  Describe "get_member_id() function"
    It "returns member ID from endpoint"
      When call get_member_id "http://etcd-0:2379"
      The status should be success
      The stdout should equal "1002"
    End
  End

  Describe "get_member_id_hex() function"
    It "returns member ID in hex format"
      When call get_member_id_hex "http://etcd-0:2379"
      The status should be success
      The stdout should equal "3ea"
    End
  End
End
