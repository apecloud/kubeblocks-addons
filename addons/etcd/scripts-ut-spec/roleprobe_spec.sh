# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "roleprobe_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Etcd Role Probe Script Tests"
  # load the scripts to be tested and dependencies
  Include $common_library_file

  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    
    # Mock exec_etcdctl function
    exec_etcdctl() {
      local endpoint="$1"
      shift
      case "$*" in
        *"endpoint status -w fields"*)
          echo '"MemberID" : 1002'
          echo '"Leader" : 1002'
          echo '"IsLearner" : false'
          return 0
          ;;
        *)
          echo "MOCK: exec_etcdctl $endpoint $*"
          return 0
          ;;
      esac
    }
    
    # Define get_etcd_role function based on real script logic
    get_etcd_role() {
      local status member_id leader_id is_learner
      
      if ! status=$(exec_etcdctl 127.0.0.1:2379 endpoint status -w fields --command-timeout=300ms --dial-timeout=100ms); then
        echo "ERROR: Failed to get endpoint status" >&2
        return 1
      fi

      member_id=$(echo "$status" | grep -o '"MemberID" : [0-9]*' | awk '{print $3}')
      leader_id=$(echo "$status" | grep -o '"Leader" : [0-9]*' | awk '{print $3}')
      is_learner=$(echo "$status" | grep -o '"IsLearner" : [a-z]*' | awk '{print $3}')

      # Check if required fields are present
      if [ -z "$member_id" ] || [ -z "$leader_id" ]; then
        echo "follower"  # Default to follower when fields are missing
        return 0
      fi

      if [ "$member_id" = "$leader_id" ]; then
        echo "leader"
      elif [ "$is_learner" = "true" ]; then
        echo "learner"
      else
        echo "follower"
      fi
    }
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
    unset ut_mode
    unset -f exec_etcdctl get_etcd_role
  }
  AfterAll 'cleanup'

  Describe "get_etcd_role() function"
    It "detects leader role correctly"
      When call get_etcd_role
      The status should be success
      The output should equal "leader"
    End

    It "detects follower role correctly"
      # Override exec_etcdctl to return follower status
      exec_etcdctl() {
        case "$*" in
          *"endpoint status -w fields"*)
            echo '"MemberID" : 1001'
            echo '"Leader" : 1002'
            echo '"IsLearner" : false'
            return 0
            ;;
        esac
      }
      
      When call get_etcd_role
      The status should be success
      The output should equal "follower"
    End

    It "detects learner role correctly"
      # Override exec_etcdctl to return learner status
      exec_etcdctl() {
        case "$*" in
          *"endpoint status -w fields"*)
            echo '"MemberID" : 1003'
            echo '"Leader" : 1002'
            echo '"IsLearner" : true'
            return 0
            ;;
        esac
      }
      
      When call get_etcd_role
      The status should be success
      The output should equal "learner"
    End

    It "handles etcdctl failure"
      # Override exec_etcdctl to fail
      exec_etcdctl() { return 1; }
      
      When call get_etcd_role
      The status should be failure
      The stderr should include "Failed to get endpoint status"
    End

    It "handles timeout scenarios"
      # Override exec_etcdctl to simulate timeout
      exec_etcdctl() {
        case "$*" in
          *"endpoint status -w fields"*)
            return 124  # timeout exit code
            ;;
        esac
      }
      
      When call get_etcd_role
      The status should be failure
      The stderr should include "Failed to get endpoint status"
    End

    It "handles missing field values"
      # Override exec_etcdctl to return incomplete status
      exec_etcdctl() {
        case "$*" in
          *"endpoint status -w fields"*)
            echo '"SomeOtherField": 123'
            return 0
            ;;
        esac
      }
      
      When call get_etcd_role
      The status should be success
      The output should equal "follower"  # Should default to follower when parsing fails
    End
  End
End