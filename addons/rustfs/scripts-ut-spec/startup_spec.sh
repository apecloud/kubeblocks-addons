# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "startup_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "RustFS startup bash script tests"
  Include ../scripts/startup.sh

  Describe "default_parity_count()"
    It "returns 0 for 1 drive"
      When call default_parity_count 1
      The output should equal "0"
    End

    It "returns 1 for 2 drives"
      When call default_parity_count 2
      The output should equal "1"
    End

    It "returns 1 for 3 drives"
      When call default_parity_count 3
      The output should equal "1"
    End

    It "returns 2 for 4 drives"
      When call default_parity_count 4
      The output should equal "2"
    End

    It "returns 2 for 5 drives"
      When call default_parity_count 5
      The output should equal "2"
    End

    It "returns 3 for 6 drives"
      When call default_parity_count 6
      The output should equal "3"
    End

    It "returns 4 for 8 drives"
      When call default_parity_count 8
      The output should equal "4"
    End

    It "returns 4 for 16 drives"
      When call default_parity_count 16
      The output should equal "4"
    End
  End

  Describe "drives_per_set()"
    It "returns pool_size for small pools (4)"
      When call drives_per_set 4
      The output should equal "4"
      The status should be success
    End

    It "returns pool_size for pools up to 16"
      When call drives_per_set 16
      The output should equal "16"
      The status should be success
    End

    It "returns largest factor in [2,16] for 24 drives"
      When call drives_per_set 24
      The output should equal "12"
      The status should be success
    End

    It "returns 5 for 25 drives (25=5x5)"
      When call drives_per_set 25
      The output should equal "5"
      The status should be success
    End

    It "returns 16 for 32 drives"
      When call drives_per_set 32
      The output should equal "16"
      The status should be success
    End

    It "fails for 17 drives (prime, no factor in [2,16])"
      When call drives_per_set 17
      The output should equal "0"
      The status should be failure
      The error should include "not divisible"
    End
  End

  Describe "validate_pool_sizes()"
    It "passes for single pool with 4 drives"
      When call validate_pool_sizes "4"
      The status should be success
    End

    It "passes for single pool with 2 drives"
      When call validate_pool_sizes "2"
      The status should be success
    End

    It "passes for equal-size pools 4,8 (two 4-drive pools)"
      When call validate_pool_sizes "4,8"
      The status should be success
    End

    It "passes for 4,7 (pool1=4 drives, pool2=3 drives, parity=2, data=1)"
      When call validate_pool_sizes "4,7"
      The status should be success
    End

    It "fails for 4,6 (pool2=2 drives, inherited parity=2, data=0)"
      When call validate_pool_sizes "4,6"
      The status should be failure
      The error should include "TooFewDataShards"
    End

    It "fails for 4,5 (pool2=1 drive, inherited parity=2, data=-1)"
      When call validate_pool_sizes "4,5"
      The status should be failure
      The error should include "TooFewDataShards"
    End

    It "passes for 2,4 (pool1=2 drives parity=1, pool2=2 drives, data=1)"
      When call validate_pool_sizes "2,4"
      The status should be success
    End

    It "passes for 3,6,9 (pool1=3 parity=1, all pools >=2)"
      When call validate_pool_sizes "3,6,9"
      The status should be success
    End

    It "fails for 6,8 (pool1=6 parity=3, pool2=2 drives, data=-1)"
      When call validate_pool_sizes "6,8"
      The status should be failure
      The error should include "TooFewDataShards"
    End

    It "passes for 1 (single node, parity=0)"
      When call validate_pool_sizes "1"
      The status should be success
    End

    It "passes for 25,28 (pool0 dps=5 parity=2, pool1=3 dps=3, data=1)"
      When call validate_pool_sizes "25,28"
      The status should be success
    End

    It "passes for 16,32 (pool0 dps=16 parity=4, pool1=16 dps=16, data=12)"
      When call validate_pool_sizes "16,32"
      The status should be success
    End
  End
End
