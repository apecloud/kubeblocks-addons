# shellcheck shell=bash

Describe "RustFS capability contract"
  It "does not register generic database backup or restore resources"
    When run sh ./no_dataprotection_contract_test.sh
    The status should be success
    The output should include "rustfs no-dataprotection contract test passed"
  End
End
