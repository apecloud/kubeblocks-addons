#!/usr/bin/env shellspec
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "switchover_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Switchover Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"

    # Setup test environment variables
    export HOSTNAME="etcd-0"
    export KB_SWITCHOVER_CURRENT_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
    export KB_SWITCHOVER_CANDIDATE_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"
    export PEER_ENDPOINT=""

    # Mock functions
    get_endpoint_adapt_lb() {
      local lb_endpoints="$1"
      local pod_name="$2"
      local result_endpoint="$3"
      echo "$result_endpoint"
    }

    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    }

    error_exit() {
      echo "ERROR: $1" >&2
      return 1
    }

    # Default: etcd-0 is leader
    is_leader() {
      case "$1" in
        "etcd-0.etcd-headless.default.svc.cluster.local:2379") return 0 ;;
        *) return 1 ;;
      esac
    }

    get_member_id_hex() {
      echo "abc123"
    }

    get_member_id() {
      echo "1001"
    }

    exec_etcdctl() {
      local endpoint="$1"
      shift
      case "$1" in
        "move-leader")
          echo "Leadership transferred"
          return 0
          ;;
        "member")
          case "$2" in
            "list")
              echo '"ID": 1002'
              echo '"ID": 1003'
              return 0
              ;;
          esac
          ;;
        *)
          echo "MOCK: exec_etcdctl $endpoint $*"
          return 0
          ;;
      esac
    }

    switchover_with_candidate() {
      local current_pod_name candidate_pod_name current_endpoint candidate_endpoint candidate_id

      current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
      candidate_pod_name="${KB_SWITCHOVER_CANDIDATE_FQDN%%.*}"

      current_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$current_pod_name" "$KB_SWITCHOVER_CURRENT_FQDN")
      candidate_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$candidate_pod_name" "$KB_SWITCHOVER_CANDIDATE_FQDN")

      local current_is_leader=false candidate_is_leader=false
      is_leader "$current_endpoint:2379" && current_is_leader=true
      is_leader "$candidate_endpoint:2379" && candidate_is_leader=true

      if [[ "$current_is_leader" == "false" ]]; then
        if [[ "$candidate_is_leader" == "true" ]]; then
          log "Leader has already changed to candidate, no switchover needed"
          return 0
        fi
        error_exit "Current ($current_pod_name) is not leader and candidate ($candidate_pod_name) is not leader either"
        return 1
      fi

      candidate_id=$(get_member_id_hex "$candidate_endpoint:2379")
      exec_etcdctl "$current_endpoint:2379" move-leader "$candidate_id" || { error_exit "Failed to transfer leadership to candidate"; return 1; }
      log "Switchover to candidate $KB_SWITCHOVER_CANDIDATE_FQDN completed successfully"
    }

    switchover_without_candidate() {
      local current_pod_name current_endpoint leader_id peers_id candidate_id candidate_id_hex

      current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
      current_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$current_pod_name" "$KB_SWITCHOVER_CURRENT_FQDN")

      if ! is_leader "$current_endpoint:2379"; then
        log "Current ($current_pod_name) is no longer leader, switchover already happened"
        return 0
      fi

      leader_id=$(get_member_id "$current_endpoint:2379")
      peers_id=$(exec_etcdctl "$current_endpoint:2379" member list -w fields | awk -F': ' '/^"ID"/ {gsub(/[^0-9]/, "", $2); print $2}')
      candidate_id=$(echo "$peers_id" | grep -v "$leader_id" | head -1)
      [ -z "$candidate_id" ] && { error_exit "No candidate found for switchover"; return 1; }
      candidate_id_hex=$(printf "%x" "$candidate_id")

      exec_etcdctl "$current_endpoint:2379" move-leader "$candidate_id_hex" || { error_exit "Failed to transfer leadership"; return 1; }
      log "Switchover completed successfully - current node is no longer leader"
    }

    switchover() {
      local current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
      if [[ "$HOSTNAME" != "$current_pod_name" ]]; then
        log "This pod ($HOSTNAME) is not the switchover current ($current_pod_name). Skipping."
        return 0
      fi

      if [ -n "$KB_SWITCHOVER_CANDIDATE_FQDN" ]; then
        switchover_with_candidate || return 1
      else
        switchover_without_candidate || return 1
      fi

      log "Switchover completed successfully"
    }
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
    unset ut_mode HOSTNAME KB_SWITCHOVER_CURRENT_FQDN KB_SWITCHOVER_CANDIDATE_FQDN PEER_ENDPOINT
    unset -f get_endpoint_adapt_lb log error_exit is_leader get_member_id_hex get_member_id exec_etcdctl
    unset -f switchover_with_candidate switchover_without_candidate switchover
  }
  AfterAll 'cleanup'

  Describe "switchover() function"
    It "performs switchover successfully with specific candidate"
      When call switchover
      The status should be success
      The stdout should include "Leadership transferred"
      The stdout should include "Switchover to candidate"
      The stdout should include "completed successfully"
    End

    It "performs automatic switchover when no candidate specified"
      unset KB_SWITCHOVER_CANDIDATE_FQDN

      When call switchover
      The status should be success
      The stdout should include "Leadership transferred"
      The stdout should include "Switchover completed successfully"
    End

    It "skips switchover when HOSTNAME does not match current pod"
      export HOSTNAME="etcd-2"

      When call switchover
      The status should be success
      The stdout should include "This pod (etcd-2) is not the switchover current (etcd-0). Skipping."
    End

    It "skips switchover when stale LEADER_POD_FQDN would have blocked (regression)"
      # Simulates the T06 root cause: HOSTNAME matches current (this IS the leader pod),
      # but a hypothetical stale LEADER_POD_FQDN no longer matters
      export HOSTNAME="etcd-0"
      export LEADER_POD_FQDN="etcd-2.etcd-headless.default.svc.cluster.local"

      When call switchover
      The status should be success
      The stdout should include "Leadership transferred"
      The stdout should include "completed successfully"
    End

    It "returns idempotent success when candidate is already leader"
      # current is not leader, candidate is leader — idempotent
      is_leader() {
        case "$1" in
          "etcd-1.etcd-headless.default.svc.cluster.local:2379") return 0 ;;
          *) return 1 ;;
        esac
      }
      export KB_SWITCHOVER_CANDIDATE_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"

      When call switchover
      The status should be success
      The stdout should include "Leader has already changed to candidate"
    End

    It "fails when neither current nor candidate is leader"
      is_leader() { return 1; }
      export KB_SWITCHOVER_CANDIDATE_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"

      When call switchover
      The status should be failure
      The stderr should include "is not leader and candidate"
      The stderr should include "is not leader either"
    End

    It "handles move-leader failure"
      exec_etcdctl() {
        local endpoint="$1"; shift
        if [ "$1" = "move-leader" ]; then
            echo "etcdctl move-leader failed" >&2
            return 1
        fi
        echo "MOCK: exec_etcdctl $endpoint $*"
        return 0
      }

      When call switchover
      The status should be failure
      The stderr should include "ERROR: Failed to transfer leadership to candidate"
    End
  End
End
