# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "startup_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "RustFS startup bash script tests"
  Include ../scripts/startup.sh

  validate_with_erasure_set_drive_count() {
    export RUSTFS_ERASURE_SET_DRIVE_COUNT="$1"
    validate_pool_sizes "$2"
    status=$?
    unset RUSTFS_ERASURE_SET_DRIVE_COUNT
    return "$status"
  }

  validate_with_standard_storage_class() {
    export RUSTFS_STORAGE_CLASS_STANDARD="$1"
    validate_pool_sizes "$2"
    status=$?
    unset RUSTFS_STORAGE_CLASS_STANDARD
    return "$status"
  }

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

    It "uses the configured erasure set drive count for every pool"
      When call validate_with_erasure_set_drive_count "3" "12,15"
      The status should be success
    End

    It "treats an explicit zero erasure set drive count as automatic layout"
      When call validate_with_erasure_set_drive_count "0" "4,8"
      The status should be success
    End

    It "accepts the leading plus syntax accepted by Rust usize parsing"
      When call validate_with_erasure_set_drive_count "+3" "12,15"
      The status should be success
    End

    It "fails the same history without the configured erasure set drive count"
      When call validate_pool_sizes "12,15"
      The status should be failure
      The error should include "TooFewDataShards"
    End

    It "rejects an erasure set drive count that cannot divide a later pool"
      When call validate_with_erasure_set_drive_count "4" "8,10"
      The status should be failure
      The error should include "RUSTFS_ERASURE_SET_DRIVE_COUNT=4"
    End

    It "accepts a numeric erasure set override in single-node mode where RustFS ignores the layout override"
      When call validate_with_erasure_set_drive_count "4" "1"
      The status should be success
    End

    It "accepts erasure set drive count one after parsing in single-node mode"
      When call validate_with_erasure_set_drive_count "1" "1"
      The status should be success
    End

    It "accepts the largest 64-bit erasure set drive count after parsing in single-node mode"
      When call validate_with_erasure_set_drive_count "18446744073709551615" "1"
      The status should be success
    End

    It "rejects a set drive count outside the 64-bit Rust usize range before the single-node bypass"
      When call validate_with_erasure_set_drive_count "18446744073709551616" "1"
      The status should be failure
      The error should include "outside the supported 64-bit unsigned integer range"
    End

    It "rejects an empty erasure set drive count before single-node startup"
      When call validate_with_erasure_set_drive_count "" "1"
      The status should be failure
      The error should include "must be a non-negative decimal integer"
    End

    It "rejects an unsupported erasure set drive count"
      When call validate_with_erasure_set_drive_count "1" "4"
      The status should be failure
      The error should include "supported divisor in [2,16]"
    End

    It "rejects an oversized erasure set drive count before shell arithmetic"
      When call validate_with_erasure_set_drive_count "18446744073709551615" "4"
      The status should be failure
      The error should include "supported divisor in [2,16]"
    End

    It "uses configured STANDARD parity instead of the default parity"
      When call validate_with_standard_storage_class "EC:1" "4,6"
      The status should be success
    End

    It "accepts zero STANDARD parity"
      When call validate_with_standard_storage_class "EC:0" "4,5"
      The status should be success
    End

    It "accepts STANDARD parity equal to half of the first set"
      When call validate_with_standard_storage_class "EC:2" "4,8"
      The status should be success
    End

    It "accepts STANDARD parity with the Rust usize leading plus syntax"
      When call validate_with_standard_storage_class "EC:+1" "4,6"
      The status should be success
    End

    It "accepts STANDARD parity with leading zeroes"
      When call validate_with_standard_storage_class "EC:01" "4,6"
      The status should be success
    End

    It "treats an empty STANDARD value as default parity"
      When call validate_with_standard_storage_class "" "4,6"
      The status should be failure
      The error should include "TooFewDataShards"
    End

    It "rejects malformed STANDARD storage class values"
      When call validate_with_standard_storage_class "RS:1" "4,6"
      The status should be failure
      The error should include "RUSTFS_STORAGE_CLASS_STANDARD"
    End

    It "rejects STANDARD parity larger than half of the first set"
      When call validate_with_standard_storage_class "EC:3" "4,8"
      The status should be failure
      The error should include "less than or equal to 2"
    End

    It "rejects STANDARD parity outside the 64-bit Rust usize range before shell arithmetic"
      When call validate_with_standard_storage_class "EC:18446744073709551616" "4,8"
      The status should be failure
      The error should include "outside the supported 64-bit unsigned integer range"
    End
  End
End
