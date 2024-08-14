# shellcheck shell=bash
# shellcheck disable=SC2034

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Redis Sentinel Offline Script Tests"

  Include ../scripts/redis-sentinel-offline.sh
  Include $common_library_file

  setup() {
    export KB_LEAVE_MEMBER_POD_IP="127.0.0.3"
    export KB_LEAVE_MEMBER_POD_NAME="sentinel-2"
    export KB_MEMBER_ADDRESSES="sentinel-0.redis-sentinel-headless:26379,sentinel-1.redis-sentinel-headless:26379,sentinel-2.redis-sentinel-headless:26379"
    export SENTINEL_PASSWORD="sentinel_password"
    sentinel_leave_member_name=""
    sentinel_leave_member_ip=""
    sentinel_pod_list=()

    ut_mode="true"
  }
  BeforeAll "setup"

  cleanup() {
    unset KB_LEAVE_MEMBER_POD_IP
    unset KB_LEAVE_MEMBER_POD_NAME
    unset KB_MEMBER_ADDRESSES
    unset SENTINEL_PASSWORD
    unset sentinel_leave_member_name
    unset sentinel_leave_member_ip
    unset sentinel_pod_list
  }
  AfterAll "cleanup"

  Describe "redis_sentinel_member_get function"
    It "correctly sets the sentinel leave member details and populates the sentinel pod list"
      When call redis_sentinel_member_get
      The variable sentinel_leave_member_name should eq "sentinel-2"
      The variable sentinel_leave_member_ip should eq "127.0.0.3"

      The variable sentinel_pod_list[0] should eq "sentinel-0.redis-sentinel-headless:26379"
      The variable sentinel_pod_list[1] should eq "sentinel-1.redis-sentinel-headless:26379"
      The variable sentinel_pod_list[2] should eq "sentinel-2.redis-sentinel-headless:26379"
    End
  End

  Describe "redis_sentinel_remove_monitor function"
    It "when one master are disconnected"
      redis_sentinel_get_masters() {
        temp_output="flags
        master,disconnected"
      }
      When call redis_sentinel_remove_monitor
      The stdout should include "one or more masters are disconnected"
    End 
  End

  Describe "check_all_sentinel_agreement function"
      setup() {
        sentinel_pod_list=("sentinel-0.redis-sentinel-headless:26379" "sentinel-1.redis-sentinel-headless:26379" "sentinel-2.redis-sentinel-headless:26379")
      }
      Before 'setup'

      un_setup() {
        unset sentinel_pod_list
      }
      After 'un_setup'

      It "when one master are disconnected"
        redis_sentinel_get_masters() {
          temp_output="flags
          master,disconnected"
        }
        When call check_all_sentinel_agreement
        The stdout should include "one or more masters are disconnected"
      End 

      It "when the number of slaves are the same"
        redis_sentinel_get_masters() {
          temp_output="name
          mymaster
          flags
          master
          num-other-sentinels
          1"
        }
        When call check_all_sentinel_agreement
        The stdout should include "all masters are reachable"
        The stdout should include "all the sentinels agree about the number of sentinels currently active"
      End

  End
End