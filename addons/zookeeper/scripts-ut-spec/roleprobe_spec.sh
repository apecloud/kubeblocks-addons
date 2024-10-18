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
    It "returns standalone mode"
      java() {
        echo "Mode: standalone"
      }

      When call get_zookeeper_mode
      The output should eq "standalone"
    End

    It "returns leader mode"
      java() {
        echo "Mode: leader"
      }

      When call get_zookeeper_mode
      The output should eq "leader"
    End

    It "returns follower mode"
      java() {
        echo "Mode: follower"
      }

      When call get_zookeeper_mode
      The output should eq "follower"
    End
  End

  Describe "load_zk_env()"
    setup() {
      touch $zk_env_file
      echo "#!/bin/bash" > $zk_env_file
      echo "export ZOO_LOG_DIR=/var/log/zookeeper" >> $zk_env_file
      echo "export ZOO_LOG4J_PROP=INFO,ROLLINGFILE" >> $zk_env_file
      chmod +x $zk_env_file
    }
    Before "setup"

    un_setup() {
      rm -rf $zk_env_file
      unset ZOO_LOG_DIR
      unset ZOO_LOG4J_PROP
    }
    After "un_setup"

    It "loads zkEnv.sh and sets environment variables"
      When call load_zk_env
      The variable ZOO_LOG_DIR should eq "/var/log/zookeeper"
      The variable ZOO_LOG4J_PROP should eq "INFO,ROLLINGFILE"
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