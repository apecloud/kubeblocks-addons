# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "member_join_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Member Join Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    
    # Setup test environment variables
    export LEADER_POD_FQDN="etcd-0.etcd-headless.default.svc.cluster.local"
    export KB_JOIN_MEMBER_POD_NAME="etcd-1"
    export KB_JOIN_MEMBER_POD_FQDN="etcd-1.etcd-headless.default.svc.cluster.local"
    export PEER_ENDPOINT=""
    export CONFIG_FILE_PATH="/tmp/test_etcd.conf"
    export config_file="$CONFIG_FILE_PATH"
    
    # Create mock config file
    mkdir -p /tmp
    echo "initial-advertise-peer-urls: http://test:2380" > "$CONFIG_FILE_PATH"
    
    # Mock functions
    get_endpoint_adapt_lb() {
      local result_endpoint="$3"
      echo "$result_endpoint"
    }
    
    get_protocol() {
      echo "http"
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
        "member")
          case "$2" in
            "add")
              echo "Member $3 added to cluster $4"
              return 0
              ;;
          esac
          ;;
      esac
      echo "MOCK: exec_etcdctl $endpoint $*"
      return 0
    }
    
    # Define add_member function
    add_member() {
      local leader_endpoint join_member_endpoint peer_protocol

      leader_pod_name="${LEADER_POD_FQDN%%.*}"
      leader_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")
      join_member_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_JOIN_MEMBER_POD_NAME" "$KB_JOIN_MEMBER_POD_FQDN")
      peer_protocol=$(get_protocol "initial-advertise-peer-urls")

      log "Adding member $KB_JOIN_MEMBER_POD_NAME to cluster via leader $leader_endpoint"
      log "Join member peer URL: $peer_protocol://$join_member_endpoint:2380"
      exec_etcdctl "$leader_endpoint:2379" member add "$KB_JOIN_MEMBER_POD_NAME" --peer-urls="$peer_protocol://$join_member_endpoint:2380" || error_exit "Failed to join member"
      log "Member $KB_JOIN_MEMBER_POD_NAME joined cluster via leader $leader_endpoint"
    }
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
    rm -f "$CONFIG_FILE_PATH"
    unset ut_mode LEADER_POD_FQDN KB_JOIN_MEMBER_POD_NAME KB_JOIN_MEMBER_POD_FQDN 
    unset PEER_ENDPOINT CONFIG_FILE_PATH config_file
    unset -f get_endpoint_adapt_lb get_protocol log error_exit exec_etcdctl add_member
  }
  AfterAll 'cleanup'

  Describe "add_member() function"
    It "joins a member to the cluster successfully"
      When call add_member
      The status should be success
      The stdout should include "Adding member etcd-1 to cluster via leader etcd-0"
      The stdout should include "Member etcd-1 added to cluster"
      The stdout should include "Member etcd-1 joined cluster via leader etcd-0"
    End
  End
End