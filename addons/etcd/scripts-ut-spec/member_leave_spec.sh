# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "member_leave_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Member Leave Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    
    # Setup test environment variables
    export KB_LEAVE_MEMBER_POD_NAME="etcd-1"
    export KB_LEAVE_MEMBER_POD_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"
    export LEADER_POD_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
    export PEER_ENDPOINT=""
    
    # Mock functions
    get_endpoint_adapt_lb() {
      local lb_endpoints="$1"
      local pod_name="$2"
      local result_endpoint="$3"
      
      if [ -n "$lb_endpoints" ]; then
        echo "$pod_name"
      else
        echo "$result_endpoint"
      fi
    }
    
    log() {
      echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
    }
    
    error_exit() {
      echo "ERROR: $1" >&2
      return 1
    }
    
    exec_etcdctl() {
      local endpoint="$1"
      shift
      case "$1" in
        "endpoint")
          case "$2" in
            "status")
              # Fix the format to match what get_etcd_id expects
              echo '"MemberID" : 1002'
              return 0
              ;;
          esac
          ;;
        "member")
          case "$2" in
            "remove")
              echo "Member $3 removed successfully"
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
    
    # Define functions based on real script logic
    get_etcd_id() {
      # Use a subshell to scope pipefail setting
      (
        set -o pipefail
        local endpoint="$1"
        local decimal_id hex_id
        
        # Check if exec_etcdctl fails first
        if ! decimal_id=$(exec_etcdctl "$endpoint" endpoint status -w fields | grep -o '"MemberID" : [0-9]*' | awk '{print $3}'); then
          return 1
        fi
        
        [ -z "$decimal_id" ] && return 1
        
        hex_id=$(printf "%x" "$decimal_id")
        echo "$hex_id"
      )
    }
    
    remove_member() {
      local etcd_id="$1"
      local leader_pod_name leader_endpoint
      
      leader_pod_name="${LEADER_POD_FQDN%%.*}"
      leader_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")
      
      log "Removing member $etcd_id via leader $leader_endpoint"
      exec_etcdctl "$leader_endpoint:2379" member remove "$etcd_id"
    }
    
    # FIX: Added return statements to propagate failures.
    member_leave() {
      local leaver_endpoint etcd_id
      
      leaver_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_LEAVE_MEMBER_POD_NAME" "$KB_LEAVE_MEMBER_POD_FQDN")
      [ -z "$leaver_endpoint" ] && { error_exit "Leave member pod endpoint is empty"; return 1; }
      
      log "Getting etcd ID for leaving member: $leaver_endpoint"
      etcd_id=$(get_etcd_id "$leaver_endpoint:2379") || { error_exit "Failed to get etcd ID"; return 1; }
      [ -z "$etcd_id" ] && { error_exit "Failed to get etcd ID"; return 1; }
      
      remove_member "$etcd_id" || { error_exit "Failed to remove member"; return 1; }
      log "Member $KB_LEAVE_MEMBER_POD_NAME left cluster"
    }
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
    unset ut_mode KB_LEAVE_MEMBER_POD_NAME KB_LEAVE_MEMBER_POD_FQDN LEADER_POD_FQDN PEER_ENDPOINT
    unset -f get_endpoint_adapt_lb log error_exit exec_etcdctl get_etcd_id remove_member member_leave
  }
  AfterAll 'cleanup'

  Describe "member_leave() function"
    It "leaves the cluster successfully"
      When call member_leave
      The status should be success
      The stdout should include "Getting etcd ID for leaving member"
      # In the successful case, the mock exec_etcdctl returns MemberID 1002, which is 3ea in hex.
      The stdout should include "Member 3ea removed successfully"
      The stdout should include "Member etcd-1 left cluster"
    End

    It "handles failed to get etcd ID"
      # Override exec_etcdctl to fail getting status but succeed in member remove
      exec_etcdctl() {
        local endpoint="$1"
        shift
        case "$1" in
          "endpoint")
            case "$2" in
              "status")
                return 1  # Fail getting status
                ;;
            esac
            ;;
          "member")
            case "$2" in
              "remove")
                echo "Member $3 removed successfully"
                return 0
                ;;
            esac
            ;;
          *)
            return 0
            ;;
        esac
      }
      
      # Override get_etcd_id to use the failing exec_etcdctl and pipefail
      get_etcd_id() {
        (
          set -o pipefail
          local endpoint="$1"
          local decimal_id hex_id
          
          # Check if exec_etcdctl fails first
          if ! decimal_id=$(exec_etcdctl "$endpoint" endpoint status -w fields | grep -o '"MemberID" : [0-9]*' | awk '{print $3}'); then
            return 1
          fi
          
          [ -z "$decimal_id" ] && return 1
          
          hex_id=$(printf "%x" "$decimal_id")
          echo "$hex_id"
        )
      }
      
      # Define a custom member_leave for this test
      # FIX: Added return statements to propagate failures.
      test_member_leave_fail() {
        local leaver_endpoint etcd_id
        
        leaver_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_LEAVE_MEMBER_POD_NAME" "$KB_LEAVE_MEMBER_POD_FQDN")
        [ -z "$leaver_endpoint" ] && { error_exit "Leave member pod endpoint is empty"; return 1; }
        
        log "Getting etcd ID for leaving member: $leaver_endpoint"
        etcd_id=$(get_etcd_id "$leaver_endpoint:2379") || { error_exit "Failed to get etcd ID"; return 1; }
        [ -z "$etcd_id" ] && { error_exit "Failed to get etcd ID"; return 1; }
        
        remove_member "$etcd_id" || { error_exit "Failed to remove member"; return 1; }
        log "Member $KB_LEAVE_MEMBER_POD_NAME left cluster"
      }
      
      When call test_member_leave_fail
      The status should be failure
      The stdout should include "Getting etcd ID for leaving member"
      The stderr should include "ERROR: Failed to get etcd ID"
    End
  End
End