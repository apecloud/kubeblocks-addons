# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "roleprobe_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "ZooKeeper Startup Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/roleprobe.sh

  init() {
    zk_env_file="./zkEnv.sh"
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $zk_env_file;
  }
  AfterAll 'cleanup'

  Describe "get_zookeeper_mode()"
    It "java returns standalone mode"
      get_zk_mode_from_script() {
        echo "Mode: standalone"
      }
      command() {
        return 1
      }

      When call get_zookeeper_mode
      The output should eq "standalone"
    End

    It "java returns leader mode"
      get_zk_mode_from_script() {
        echo "Mode: leader"
      }
      command() {
        return 1
      }

      When call get_zookeeper_mode
      The output should eq "leader"
    End

    It "java returns follower mode"
      get_zk_mode_from_script() {
        echo "Mode: follower"
      }
      command() {
        return 1
      }

      When call get_zookeeper_mode
      The output should eq "follower"
    End

    It "nc returns standalone mode"
      nc() {
        echo "Mode: standalone"
      }

      command() {
        return 0
      }

      When call get_zookeeper_mode
      The output should eq "standalone"
    End

    It "nc returns leader mode"
      nc() {
        echo "Mode: leader"
      }
      command() {
        return 0
      }
      When call get_zookeeper_mode
      The output should eq "leader"
    End

    It "nc returns follower mode"
      nc() {
        echo "Mode: follower"
      }
      command() {
        return 0
      }
      When call get_zookeeper_mode
      The output should eq "follower"
    End
  End

  Describe "get_zk_role()"
    It "returns leader when mode is standalone"
      get_zookeeper_mode() {
        echo "standalone"
      }

      When call get_zk_role
      The output should eq "leader"
    End

    It "returns leader when mode is leader"
      get_zookeeper_mode() {
        echo "leader"
      }

      When call get_zk_role
      The output should eq "leader"
    End

    It "returns follower when mode is follower"
      get_zookeeper_mode() {
        echo "follower"
      }

      When call get_zk_role
      The output should eq "follower"
    End
  End
End