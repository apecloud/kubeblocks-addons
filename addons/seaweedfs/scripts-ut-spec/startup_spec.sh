# shellcheck shell=sh
Describe 'SeaweedFS startup and lifecycle process contracts'
  It 'passes offline behavior tests without starting a database'
    When run python3 ../tests/test_scripts.py
    The status should be success
    The stderr should include 'OK'
  End
End
