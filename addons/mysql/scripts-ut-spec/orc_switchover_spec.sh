# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "ORC switchover script tests"
  Include ../scripts/orc-switchover.sh

  Describe "MySQL read flag parsing"
    It "recognizes writable flags after mysql client stderr noise"
      output=$(printf '%s\n%s\n' \
        'mysql: [Warning] Using a password on the command line interface can be insecure.' \
        '0	0')

      When call is_writable_mysql "$output"
      The status should be success
    End

    It "recognizes read-only flags after mysql client stderr noise"
      output=$(printf '%s\n%s\n' \
        'mysql: [Warning] Using a password on the command line interface can be insecure.' \
        '1	1')

      When call is_readonly_mysql "$output"
      The status should be success
    End

    It "rejects output without a read_only/super_read_only row"
      output='mysql: [Warning] Using a password on the command line interface can be insecure.'

      When call is_writable_mysql "$output"
      The status should be failure
    End
  End
End
