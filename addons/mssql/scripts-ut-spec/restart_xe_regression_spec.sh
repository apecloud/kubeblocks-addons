# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# shellcheck shell=bash

Describe "SQL Server restart and slow-query regressions"
  It "preserves restart configure identity while readiness is withheld"
    When run bash ../tests/restart_init_flag_lifecycle_test.sh
    The status should be success
    The output should include "Total: 4 passed, 0 failed"
  End

  It "escapes and bootstraps the slow-query XE event-file target"
    When run bash ../tests/slowquery_xe_bootstrap_test.sh
    The status should be success
    The output should include "Total: 4 passed, 0 failed"
  End
End
