# shellcheck shell=bash

Describe "set_config_variables function"
  Include ../scripts/set_config_variables.sh

  setup() {
    export CONFIG_DIR="./conf"
    mkdir -p $CONFIG_DIR
    cat <<EOF > $CONFIG_DIR/test.cnf
[test]
valid_key1=value1
valid_key2=value2
invalid key=value3
# This is a comment
EOF
  }
  Before "setup"

  cleanup() {
    rm -rf $CONFIG_DIR
  }
  After "cleanup"

  It "sets valid configuration variables"
    When call set_config_variables "test"
    The output should include "valid_key1=value1"
    The output should include "valid_key2=value2"
    The variable valid_key1 should equal "value1"
    The variable valid_key2 should equal "value2"
  End

  It "detects invalid configuration lines"
    When call set_config_variables "test"
    The output should include "bad format: invalid key=value3"
  End

  It "ignores comments and empty lines"
    When call set_config_variables "test"
    The output should not include "# This is a comment"
  End
End