# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Elasticsearch member-leave script"
  It "keeps shard allocation exclusion on successful memberLeave"
    When run bash -c '
      export ES_MEMBER_LEAVE_UNIT_TEST=1
      export KB_LEAVE_MEMBER_POD_NAME=es-ops-data-2
      curl() { echo "{\"version\":{\"number\":\"8.8.2\"}}"; }
      jq() { echo "8.8.2"; }
      . ../scripts/member-leave.sh
      clear_shard_exclusion() {
        echo "clear_shard_exclusion $*"
      }
      cleanup
    '
    The status should be success
    The output should include "leaving shard allocation exclusion in place"
    The output should not include "clear_shard_exclusion"
  End

  It "clears shard allocation exclusion when memberLeave fails"
    When run bash -c '
      export ES_MEMBER_LEAVE_UNIT_TEST=1
      export KB_LEAVE_MEMBER_POD_NAME=es-ops-data-2
      curl() { echo "{\"version\":{\"number\":\"8.8.2\"}}"; }
      jq() { echo "8.8.2"; }
      . ../scripts/member-leave.sh
      clear_shard_exclusion() {
        echo "clear_shard_exclusion $*"
      }
      set +e
      false
      cleanup
    '
    The status should be failure
    The output should include "clear_shard_exclusion es-ops-data-2"
  End
End
