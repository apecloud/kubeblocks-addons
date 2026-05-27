# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Elasticsearch post-start hook"
  source_post_start_hook() {
    export ES_POST_START_UNIT_TEST=1
    export POD_NAME="${POD_NAME:-es-ops-data-2}"
    export POD_IP="${POD_IP:-127.0.0.1}"
    export TLS_ENABLED="${TLS_ENABLED:-false}"
    export ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-test-pass}"
    . ../scripts/post-start-hook.sh
  }

  It "clears stale allocation exclusion when it exactly matches POD_NAME"
    When run bash -c '
      source_post_start_hook() {
        export ES_POST_START_UNIT_TEST=1
        export POD_NAME=es-ops-data-2
        export POD_IP=127.0.0.1
        export TLS_ENABLED=false
        export ELASTIC_PASSWORD=test-pass
        . ../scripts/post-start-hook.sh
      }
      source_post_start_hook
      curl() {
        case "$*" in
          *"_cluster/health?local=true"*) echo "{\"status\":\"green\"}"; return 0 ;;
          *"_cluster/settings?include_defaults=false"*) echo "{\"persistent\":{\"cluster\":{\"routing\":{\"allocation\":{\"exclude\":{\"_name\":\"es-ops-data-2\"}}}}}}"; return 0 ;;
          *"_cluster/settings"*) echo "PUT_CLEAR $*"; return 0 ;;
        esac
        return 1
      }
      jq() { echo "es-ops-data-2"; }
      clear_stale_allocation_exclusion_for_self
    '
    The status should be success
    The output should include "clearing stale shard allocation exclusion for es-ops-data-2"
    The output should include "PUT_CLEAR"
  End

  It "does not clear allocation exclusion when it targets another pod"
    When run bash -c '
      source_post_start_hook() {
        export ES_POST_START_UNIT_TEST=1
        export POD_NAME=es-ops-data-2
        export POD_IP=127.0.0.1
        export TLS_ENABLED=false
        export ELASTIC_PASSWORD=test-pass
        . ../scripts/post-start-hook.sh
      }
      source_post_start_hook
      curl() {
        case "$*" in
          *"_cluster/health?local=true"*) echo "{\"status\":\"green\"}"; return 0 ;;
          *"_cluster/settings?include_defaults=false"*) echo "{\"persistent\":{\"cluster\":{\"routing\":{\"allocation\":{\"exclude\":{\"_name\":\"es-ops-data-1\"}}}}}}"; return 0 ;;
          *"_cluster/settings"*) echo "PUT_CLEAR $*"; return 0 ;;
        esac
        return 1
      }
      jq() { echo "es-ops-data-1"; }
      clear_stale_allocation_exclusion_for_self
    '
    The status should be success
    The output should include "no stale shard allocation exclusion for es-ops-data-2"
    The output should not include "PUT_CLEAR"
  End

  It "leaves stale allocation exclusion untouched when local API is not ready"
    When run bash -c '
      source_post_start_hook() {
        export ES_POST_START_UNIT_TEST=1
        export POD_NAME=es-ops-data-2
        export POD_IP=127.0.0.1
        export TLS_ENABLED=false
        export ELASTIC_PASSWORD=test-pass
        . ../scripts/post-start-hook.sh
      }
      source_post_start_hook
      seq() { echo 1; }
      sleep() { :; }
      curl() {
        case "$*" in
          *"_cluster/health?local=true"*) return 1 ;;
          *"_cluster/settings"*) echo "UNEXPECTED_SETTINGS_CALL"; return 0 ;;
        esac
        return 1
      }
      jq() { echo "es-ops-data-2"; }
      clear_stale_allocation_exclusion_for_self
    '
    The status should be success
    The output should include "local elasticsearch API is not ready, skip clearing stale shard allocation exclusion"
    The output should not include "UNEXPECTED_SETTINGS_CALL"
  End
End
