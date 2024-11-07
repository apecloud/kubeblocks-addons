# shellcheck shell=bash
# shellcheck disable=SC2317

Describe "Common Functions Tests"
  Include ../scripts/common.sh

  setup_temp_file() {
    config_file=$(mktemp)
  }

  cleanup_temp_file() {
    rm "$config_file"
  }

  Describe "check_backup_file()"
    It "returns success when backup file is valid"
      etcdutl() { echo "d1ed6c2f, 0, 6, 25 kB"; return 0; }
      export BACKUP_KEY_THRESHOLD=6
      When call check_backup_file "backup_file"
      The status should be success
    End

    It "returns failure when etcdutl fails"
      etcdutl() { return 1; }
      When call check_backup_file "backup_file"
      The status should be failure
      The stderr should include "ERROR: Failed to check the backup file with etcdctl"
    End

    It "returns failure when totalKey is not a number"
      etcdutl() { echo "d1ed6c2f, 0, not_a_number, 25 kB"; return 0; }
      When call check_backup_file "backup_file"
      The status should be failure
      The stderr should include "ERROR: snapshot totalKey is not a valid number."
    End

    It "returns failure when totalKey is less than threshold"
      etcdutl() { echo "d1ed6c2f, 0, 30, 80 kB"; return 0; }
      BACKUP_KEY_THRESHOLD=50
      When call check_backup_file "backup_file"
      The status should be failure
      The stderr should include "WARNING: snapshot totalKey is less than the threshold"
    End
  End

  Describe "get_client_protocol()"
    BeforeEach "setup_temp_file"
    AfterEach "cleanup_temp_file"

    It "returns https when advertise-client-urls contains https"
      echo "advertise-client-urls: https://etcd-0.com" > "$config_file"
      When call get_client_protocol
      The output should equal "https"
    End

    It "returns http when advertise-client-urls contains http"
      echo "advertise-client-urls: http://etcd-0.com" > "$config_file"
      When call get_client_protocol
      The output should equal "http"
    End
  End

  Describe "get_peer_protocol()"
    BeforeEach "setup_temp_file"
    AfterEach "cleanup_temp_file"

    It "returns https when initial-advertise-peer-urls contains https"
      echo "initial-advertise-peer-urls: https://etcd-0.com" > "$config_file"
      When call get_peer_protocol
      The output should equal "https"
    End

    It "returns http when initial-advertise-peer-urls contains http"
      echo "initial-advertise-peer-urls: http://etcd-0.com" > "$config_file"
      When call get_peer_protocol
      The output should equal "http"
    End
  End

  Describe "exec_etcdctl()"
    setup_empty_tls_files() {
      TLS_MOUNT_PATH=$(mktemp -d)
      touch "${TLS_MOUNT_PATH}/ca.crt"
      touch "${TLS_MOUNT_PATH}/tls.crt"
      touch "${TLS_MOUNT_PATH}/tls.key"
    }

    setup_tls_files() {
      TLS_MOUNT_PATH=$(mktemp -d)
      echo "dummy content" > "${TLS_MOUNT_PATH}/ca.crt"
      echo "dummy content" > "${TLS_MOUNT_PATH}/tls.crt"
      echo "dummy content" > "${TLS_MOUNT_PATH}/tls.key"
    }

    cleanup_tls_files() {
      rm -r "$TLS_MOUNT_PATH"
    }

    It "executes etcdctl with https and valid TLS files should be failure"
      get_client_protocol() { echo "https"; }
      setup_empty_tls_files
      etcdctl() { return 0; }
      When call exec_etcdctl "endpoints"
      The status should be failure
      The stderr should include "ERROR: bad etcdctl args: clientProtocol:https, endpoints:endpoints"
      cleanup_tls_files
    End

    It "executes etcdctl with https and valid TLS files should be success"
      get_client_protocol() { echo "https"; }
      setup_tls_files
      etcdctl() { return 0; }
      When call exec_etcdctl "endpoints"
      The status should be success
      cleanup_tls_files
    End

    It "executes etcdctl with http"
      get_client_protocol() { echo "http"; }
      etcdctl() { return 0; }
      When call exec_etcdctl "endpoints"
      The status should be success
    End

    It "fails when etcdctl command fails"
      get_client_protocol() { echo "http"; }
      etcdctl() { return 1; }
      When call exec_etcdctl "endpoints"
      The status should be failure
      The stderr should include "etcdctl command failed"
    End
  End

  Describe "get_current_leader()"
    It "returns the current leader endpoint"
      exec_etcdctl() {
        if [ "$1" = "leader_endpoint" ]; then
          echo "8e9e05c52164694d, started, default, http://etcd-0:2380, http://etcd-0:2379, false"
          echo "8e9e05c52164694d, started, default, http://etcd-1:2380, http://etcd-1:2379, false"
          echo "8e9e05c52164694d, started, default, http://etcd-2:2380, http://etcd-2:2379, false"
        elif [ "$1" = "http://etcd-0:2379,http://etcd-1:2379,http://etcd-2:2379" ]; then
          echo "etcd-0:2379, 8e9e05c52164694d, 3.5.16, 25 kB, true, false, 2, 4, 4,"
        fi
      }
      When call get_current_leader "leader_endpoint"
      The output should equal "etcd-0:2379"
    End

    It "fails when leader is not ready"
      exec_etcdctl() { return 1; }
      When call get_current_leader
      The status should be failure
      The stderr should include "leader is not ready"
    End
  End

  Describe "get_current_leader_with_retry()"
    It "retries and returns the current leader endpoint"
      call_func_with_retry() { echo "leader_endpoint"; return 0; }
      When call get_current_leader_with_retry 3 1
      The output should equal "leader_endpoint"
    End
  End
End