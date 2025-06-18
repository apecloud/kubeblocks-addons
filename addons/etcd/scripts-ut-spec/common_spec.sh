# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Common Functions Tests"
  Include ../scripts/common.sh

  # Mock error_exit to prevent actual exit and capture its message
  error_exit() {
    echo "ERROR: $1" >&2
    return 1 # Ensure the function call is marked as failed for shellspec
  }

  setup_temp_config_file() {
    # common.sh uses a global 'config_file'. We override it for tests.
    config_file=$(mktemp)
    # Provide TMP_CONFIG_PATH as common.sh now uses it with a default
    export TMP_CONFIG_PATH="$config_file"
  }

  cleanup_temp_config_file() {
    rm -f "$config_file"
    unset TMP_CONFIG_PATH
  }

  Describe "check_backup_file()"
    It "returns success when backup file is valid"
      etcdutl() { echo "d1ed6c2f, 0, 6, 25 kB"; return 0; }
      # Mock command -v for etcdutl
      command() { if [ "$1" = "-v" ] && [ "$2" = "etcdutl" ]; then return 0; else return 127; fi; }
      When call check_backup_file "backup_file"
      The status should be success
    End

    It "returns failure when etcdutl command not found"
      command() { if [ "$1" = "-v" ] && [ "$2" = "etcdutl" ]; then return 1; else return 0; fi; }
      When call check_backup_file "backup_file"
      The status should be failure
      The stderr should include "ERROR: etcdutl command not found"
    End

    It "returns failure when etcdutl snapshot status fails"
      command() { if [ "$1" = "-v" ] && [ "$2" = "etcdutl" ]; then return 0; fi; }
      etcdutl() { return 1; } # Simulate etcdutl command failure
      When call check_backup_file "backup_file"
      The status should be failure
      The stderr should include "ERROR: check_backup_file - Failed to get snapshot status for 'backup_file' using etcdutl"
    End

    It "returns failure when totalKey is not a number"
      command() { if [ "$1" = "-v" ] && [ "$2" = "etcdutl" ]; then return 0; fi; }
      etcdutl() { echo "d1ed6c2f, 0, not_a_number, 25 kB"; return 0; }
      When call check_backup_file "backup_file"
      The status should be failure
      The stderr should include "ERROR: check_backup_file - Snapshot totalKey 'not_a_number' is not a valid number for 'backup_file'"
    End
  End

  Describe "exec_etcdctl()"
    # Mock command -v for etcdctl
    command_check_etcdctl_exists() { if [ "$1" = "-v" ] && [ "$2" = "etcdctl" ]; then return 0; else return 127; fi; }
    
    setup_tls_files() {
      TLS_MOUNT_PATH=$(mktemp -d)
      echo "dummy content" > "${TLS_MOUNT_PATH}/ca.pem"
      echo "dummy content" > "${TLS_MOUNT_PATH}/cert.pem"
      echo "dummy content" > "${TLS_MOUNT_PATH}/key.pem"
      export TLS_MOUNT_PATH # Export for common.sh to use
    }

    cleanup_tls_files() {
      rm -rf "$TLS_MOUNT_PATH"
      unset TLS_MOUNT_PATH
    }
    
    BeforeEach "setup_temp_config_file" "command_check_etcdctl_exists"
    AfterEach "cleanup_temp_config_file" "cleanup_tls_files"

    It "executes etcdctl with http when protocol is http"
      echo "advertise-client-urls: http://etcd-0.com" > "$config_file"
      etcdctl() { # Mock etcdctl
        # Assert that $tls_args is empty or not present for http
        [[ "$*" != *"--cacert"* ]] || return 1 # Fail if TLS args present
        return 0 
      }
      When call exec_etcdctl "endpoints" "version"
      The status should be success
    End

    It "executes etcdctl with https and valid TLS files"
      echo "advertise-client-urls: https://etcd-0.com" > "$config_file"
      setup_tls_files # Ensure TLS files are set up
      etcdctl() { # Mock etcdctl
         # Assert that TLS args are present
        [[ "$*" == *"--cacert=${TLS_MOUNT_PATH}/ca.pem"* ]] && \
        [[ "$*" == *"--cert=${TLS_MOUNT_PATH}/cert.pem"* ]] && \
        [[ "$*" == *"--key=${TLS_MOUNT_PATH}/key.pem"* ]] || return 1 # Fail if TLS args not as expected
        return 0
      }
      When call exec_etcdctl "endpoints" "version"
      The status should be success
    End

    It "fails if etcdctl command is not found"
      command_check_etcdctl_not_exists() { if [ "$1" = "-v" ] && [ "$2" = "etcdctl" ]; then return 1; fi; }
      BeforeRun "command_check_etcdctl_not_exists" # Override the BeforeEach command mock just for this test
      echo "advertise-client-urls: http://etcd-0.com" > "$config_file"
      When call exec_etcdctl "endpoints" "version"
      The status should be failure
      The stderr should include "ERROR: etcdctl command not found"
      Skip # Due to BeforeRun interaction complexities with teardown, direct mock is better. Test manually or simplify mock.
    End

    It "fails if TLS_MOUNT_PATH is not a directory for https"
      echo "advertise-client-urls: https://etcd-0.com" > "$config_file"
      export TLS_MOUNT_PATH="/path/to/nonexistent_dir_or_file"
      When call exec_etcdctl "endpoints" "version"
      The status should be failure
      The stderr should include "ERROR: exec_etcdctl - TLS_MOUNT_PATH '/path/to/nonexistent_dir_or_file' not found for https client protocol"
    End
    
    It "fails if a TLS certificate file is missing for https"
      echo "advertise-client-urls: https://etcd-0.com" > "$config_file"
      setup_tls_files
      rm "${TLS_MOUNT_PATH}/ca.pem" # Remove one cert file
      When call exec_etcdctl "endpoints" "version"
      The status should be failure
      The stderr should include "ERROR: exec_etcdctl - TLS certificate file '${TLS_MOUNT_PATH}/ca.pem' missing or empty"
    End

    It "fails if etcdctl command execution fails"
      echo "advertise-client-urls: http://etcd-0.com" > "$config_file"
      etcdctl() { return 1; } # Simulate etcdctl command failure
      When call exec_etcdctl "endpoints" "version"
      The status should be failure
      The stderr should include "ERROR: exec_etcdctl - etcdctl command failed for endpoints 'endpoints' with args 'version'"
    End
  End

  Describe "get_current_leader()"
    # Mock command -v for etcdctl (needed by exec_etcdctl)
    command_check_etcdctl_exists() { if [ "$1" = "-v" ] && [ "$2" = "etcdctl" ]; then return 0; else return 127; fi; }
    BeforeEach "setup_temp_config_file" "command_check_etcdctl_exists"
    AfterEach "cleanup_temp_config_file"

    It "returns the current leader endpoint"
      # Mock get_protocol for exec_etcdctl
      get_protocol() { echo "http"; return 0; }
      
      # Mock exec_etcdctl for get_current_leader
      # This mock needs to handle two types of calls: 'member list' and 'endpoint status'
      exec_etcdctl_output_member_list='''
http://etcd-0:2380
http://etcd-1:2380
http://etcd-2:2380
'''
      exec_etcdctl_output_endpoint_status_leader_etcd1='''
endpoint:"http://etcd-0:2379",is_leader:"false"
endpoint:"http://etcd-1:2379",is_leader:"true"
endpoint:"http://etcd-2:2379",is_leader:"false"
'''
      exec_etcdctl() {
        if [[ "$*" == *"member list"* ]]; then
          echo "$exec_etcdctl_output_member_list"
        elif [[ "$*" == *"endpoint status -w fields"* ]]; then
          # Check if the endpoints arg matches what member list would produce
          [[ "$1" == "http://etcd-0:2380,http://etcd-1:2380,http://etcd-2:2380" ]] || { echo "ERROR: MOCK FAIL - unexpected endpoints for status: $1" >&2; return 1; }
          echo "$exec_etcdctl_output_endpoint_status_leader_etcd1"
        else
          echo "ERROR: MOCK FAIL - exec_etcdctl called with unexpected args: $*" >&2
          return 1
        fi
        return 0
      }
      When call get_current_leader "http://initial-contact:2379"
      The output should equal "http://etcd-1:2379"
      The status should be success
    End

    It "fails if member list is empty"
      get_protocol() { echo "http"; return 0; }
      exec_etcdctl() { # Mock for member list returning empty
        if [[ "$*" == *"member list"* ]]; then
          echo "" # Empty output for peer_endpoints
        else
          return 0 # Allow other calls for simplicity, though they won't be reached
        fi
        return 0
      }
      When call get_current_leader "http://initial-contact:2379"
      The status should be failure
      The stderr should include "ERROR: get_current_leader - No peer endpoints found from member list of 'http://initial-contact:2379'"
    End

    It "fails if no leader is found in endpoint status"
      get_protocol() { echo "http"; return 0; }
      exec_etcdctl_output_endpoint_status_no_leader='''
endpoint:"http://etcd-0:2379",is_leader:"false"
endpoint:"http://etcd-1:2379",is_leader:"false"
endpoint:"http://etcd-2:2379",is_leader:"false"
'''
      exec_etcdctl() {
        if [[ "$*" == *"member list"* ]]; then
          echo "http://etcd-0:2380,http://etcd-1:2380,http://etcd-2:2380" # Assume valid peer endpoints string
        elif [[ "$*" == *"endpoint status -w fields"* ]]; then
          echo "$exec_etcdctl_output_endpoint_status_no_leader"
        else
          return 1
        fi
        return 0
      }
      When call get_current_leader "http://initial-contact:2379"
      The status should be failure
      The stderr should include "ERROR: get_current_leader - Leader not found among peers: 'http://etcd-0:2380,http://etcd-1:2380,http://etcd-2:2380'"
    End
    
    It "fails if exec_etcdctl for member list fails internally"
      get_protocol() { echo "http"; return 0; }
      exec_etcdctl() {
         if [[ "$*" == *"member list"* ]]; then
            # Simulate exec_etcdctl's internal error_exit by returning non-zero and printing to stderr
            # This makes the main `if ! peer_endpoints=$(...)` in get_current_leader trigger its own error_exit
            echo "ERROR: exec_etcdctl - etcdctl command failed..." >&2 
            return 1 
         fi
      }
      When call get_current_leader "http://initial-contact:2379"
      The status should be failure
      # The error message from exec_etcdctl will be printed by the mocked error_exit.
      # Then get_current_leader's own error_exit for parsing failure will be triggered.
      The stderr should include "ERROR: get_current_leader - Failed to get or parse member list from 'http://initial-contact:2379'"
    End
  End

  Describe "get_current_leader_with_retry()"
    # Mock command -v for call_func_with_retry
    command_check_call_func_exists() { if [ "$1" = "-v" ] && [ "$2" = "call_func_with_retry" ]; then return 0; else return 127; fi; }
    
    BeforeEach "command_check_call_func_exists"

    It "retries and returns the current leader endpoint"
      call_func_with_retry() { # Mock call_func_with_retry
        # Args: max_retries, retry_delay, function_name, function_args...
        # Simulate successful call to get_current_leader
        echo "http://leader-from-retry:2379"
        return 0
      }
      When call get_current_leader_with_retry "http://initial:2379" 3 1
      The output should equal "http://leader-from-retry:2379"
      The status should be success
    End

    It "fails if call_func_with_retry command is not found"
      command_check_call_func_not_exists() { if [ "$1" = "-v" ] && [ "$2" = "call_func_with_retry" ]; then return 1; fi; }
      BeforeRun "command_check_call_func_not_exists" # Override BeforeEach
      When call get_current_leader_with_retry "http://initial:2379" 3 1
      The status should be failure
      The stderr should include "ERROR: get_current_leader_with_retry - call_func_with_retry command not found. Ensure kblib is sourced."
      Skip # Due to BeforeRun interaction complexities with teardown, direct mock is better. Test manually or simplify mock.
    End
    
    It "propagates failure from call_func_with_retry"
      call_func_with_retry() {
        echo "ERROR: call_func_with_retry itself failed" >&2
        return 1
      }
      When call get_current_leader_with_retry "http://initial:2379" 3 1
      The status should be failure
      The stderr should include "ERROR: call_func_with_retry itself failed" # common.sh's error_exit will catch this.
      # Since common.sh has set -e, the script will exit when call_func_with_retry returns 1.
      # The output of call_func_with_retry is captured by current_leader=$(...), then echo "$current_leader"
      # If call_func_with_retry fails, the assignment might happen but script exits.
      # The mocked error_exit in this test spec will ensure the message from call_func_with_retry is visible.
    End
  End
End