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

    It "returns observer when mode is observer"
      get_zookeeper_mode() {
        echo "observer"
      }

      When call get_zk_role
      The status should be success
      The output should eq "observer"
    End
  End

  Describe "roleprobe.sh behavior"
    setup_mock_nc() {
      roleprobe_mock_bin="$(mktemp -d)"
      roleprobe_original_path="$PATH"
      cat > "$roleprobe_mock_bin/nc" <<'EOF'
#!/bin/sh
case "${ROLEPROBE_NC_CASE:-}" in
  standalone|leader|follower|observer|looking)
    printf 'Mode: %s\n' "$ROLEPROBE_NC_CASE"
    ;;
  ambiguous)
    printf 'Mode: leader\nMode: follower\n'
    ;;
  empty)
    ;;
  refused)
    exit 1
    ;;
  *)
    exit 2
    ;;
esac
EOF
      chmod +x "$roleprobe_mock_bin/nc"
      export PATH="$roleprobe_mock_bin:$PATH"
    }

    cleanup_mock_nc() {
      PATH="$roleprobe_original_path"
      export PATH
      rm -rf "$roleprobe_mock_bin"
      unset roleprobe_mock_bin roleprobe_original_path ROLEPROBE_NC_CASE
    }

    BeforeEach "setup_mock_nc"
    AfterEach "cleanup_mock_nc"

    It "maps standalone to leader"
      export ROLEPROBE_NC_CASE="standalone"

      When run command bash ../scripts/roleprobe.sh
      The status should be success
      The output should eq "leader"
    End

    It "publishes leader"
      export ROLEPROBE_NC_CASE="leader"

      When run command bash ../scripts/roleprobe.sh
      The status should be success
      The output should eq "leader"
    End

    It "publishes follower"
      export ROLEPROBE_NC_CASE="follower"

      When run command bash ../scripts/roleprobe.sh
      The status should be success
      The output should eq "follower"
    End

    It "publishes observer"
      export ROLEPROBE_NC_CASE="observer"

      When run command bash ../scripts/roleprobe.sh
      The status should be success
      The output should eq "observer"
    End

    It "fails closed on empty output"
      export ROLEPROBE_NC_CASE="empty"

      When run command bash ../scripts/roleprobe.sh
      The status should be failure
      The output should eq ""
    End

    It "fails closed on an uncertain mode"
      export ROLEPROBE_NC_CASE="looking"

      When run command bash ../scripts/roleprobe.sh
      The status should be failure
      The output should eq ""
    End

    It "fails closed when nc refuses the connection"
      export ROLEPROBE_NC_CASE="refused"

      When run command bash ../scripts/roleprobe.sh
      The status should be failure
      The output should eq ""
    End

    It "fails closed on ambiguous multi-line mode output"
      export ROLEPROBE_NC_CASE="ambiguous"

      When run command bash ../scripts/roleprobe.sh
      The status should be failure
      The output should eq ""
    End
  End
End
