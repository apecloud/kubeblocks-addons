# shellcheck shell=sh

Describe "Minio replicas-history-config script tests"
  Include ../scripts/replicas-history-config.sh

  Describe "get_cm_key_new_value()"
    It "initializes history when current is empty"
      When call get_cm_key_new_value "" "2"
      The output should eq "[2]"
    End

    It "appends on scale-out (new > current max)"
      When call get_cm_key_new_value "2" "4"
      The output should eq "[2,4]"
    End

    It "does not append on scale-in (new < current max)"
      When call get_cm_key_new_value "2,4" "2"
      The output should eq "[2,4]"
    End

    It "does not append when equal to current max"
      When call get_cm_key_new_value "2,4" "4"
      The output should eq "[2,4]"
    End

    It "does not append when equal to last but less than max"
      When call get_cm_key_new_value "2,4,2" "2"
      The output should eq "[2,4,2]"
    End

    It "appends on further scale-out after scale-in"
      When call get_cm_key_new_value "2,4" "6"
      The output should eq "[2,4,6]"
    End

    It "handles single-element history with no change"
      When call get_cm_key_new_value "2" "2"
      The output should eq "[2]"
    End
  End
End
