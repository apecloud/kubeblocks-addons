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

  setup() { rm -f /tmp/stale-exclusion-cleanup.pending; }
  cleanup() { rm -f /tmp/stale-exclusion-cleanup.pending; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "clears stale allocation exclusion with readback verify"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending /tmp/shellspec_put_done
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*)
            if [ -f /tmp/shellspec_put_done ]; then
              echo "{}"
            else
              echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-2\"}"
            fi
            return 0
            ;;
          *"_cluster/settings"*) touch /tmp/shellspec_put_done; echo "PUT_CLEAR $*"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rc=$?
      rm -f /tmp/shellspec_put_done
      [ ! -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_ABSENT"
      exit $rc
    '
    The status should be success
    The output should include "clearing stale shard allocation exclusion for es-ops-data-2"
    The output should include "PUT_CLEAR"
    The output should include "MARKER_ABSENT"
  End

  It "removes only self from multi-node exclusion list with readback verify"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending /tmp/shellspec_put_done
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*)
            if [ -f /tmp/shellspec_put_done ]; then
              echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-1,es-ops-data-3\"}"
            else
              echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-1,es-ops-data-2,es-ops-data-3\"}"
            fi
            return 0
            ;;
          *"_cluster/settings"*) touch /tmp/shellspec_put_done; echo "PUT_UPDATE $*"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rm -f /tmp/shellspec_put_done
    '
    The status should be success
    The output should include "removing es-ops-data-2 from shard allocation exclusion"
    The output should include "PUT_UPDATE"
  End

  It "removes self from space-padded multi-node exclusion list"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending /tmp/shellspec_put_done
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*)
            if [ -f /tmp/shellspec_put_done ]; then
              echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-1,es-ops-data-3\"}"
            else
              echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-1, es-ops-data-2, es-ops-data-3\"}"
            fi
            return 0
            ;;
          *"_cluster/settings"*) touch /tmp/shellspec_put_done; echo "PUT_UPDATE $*"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rm -f /tmp/shellspec_put_done
    '
    The status should be success
    The output should include "removing es-ops-data-2 from shard allocation exclusion"
    The output should include "remaining: es-ops-data-1,es-ops-data-3"
    The output should include "PUT_UPDATE"
  End

  It "does not clear allocation exclusion when it targets another pod"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*) echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-1\"}"; return 0 ;;
          *"_cluster/settings"*) echo "PUT_CLEAR $*"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
    '
    The status should be success
    The output should include "no stale shard allocation exclusion for es-ops-data-2"
    The output should not include "PUT_CLEAR"
  End

  It "skips when no exclusion setting exists"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*) echo "{}"; return 0 ;;
          *"_cluster/settings"*) echo "PUT_UNEXPECTED $*"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
    '
    The status should be success
    The output should include "no shard allocation exclusion set"
    The output should not include "PUT_UNEXPECTED"
  End

  It "returns failure and writes marker when PUT to clear exclusion fails"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*) echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-2\"}"; return 0 ;;
          *"_cluster/settings"*) echo "PUT_FAIL"; return 22 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rc=$?
      [ -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_PRESENT"
      exit $rc
    '
    The status should be success
    The output should include "clearing stale shard allocation exclusion for es-ops-data-2"
    The output should include "MARKER_PRESENT"
    The error should include "stale exclusion cleanup failed"
  End

  It "writes marker and returns success when local API is not ready"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending
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
          *"_cluster/health?local=true"*) return 1 ;;
          *"_cluster/settings"*) echo "UNEXPECTED_SETTINGS_CALL"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rc=$?
      [ -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_PRESENT"
      exit $rc
    '
    The status should be success
    The output should include "writing marker for readiness probe cleanup"
    The output should include "MARKER_PRESENT"
    The output should not include "UNEXPECTED_SETTINGS_CALL"
  End

  It "writes marker and returns success when readback verify finds exclusion still present"
    When run bash -c '
      rm -f /tmp/stale-exclusion-cleanup.pending
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*) echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-2\"}"; return 0 ;;
          *"_cluster/settings"*) echo "PUT_OK"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rc=$?
      [ -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_PRESENT"
      exit $rc
    '
    The status should be success
    The error should include "readback verify failed"
    The output should include "MARKER_PRESENT"
    The error should include "stale exclusion cleanup failed"
  End

  It "removes marker when no stale exclusion exists (idempotent)"
    When run bash -c '
      touch /tmp/stale-exclusion-cleanup.pending
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
          *"_cluster/settings?include_defaults=false&flat_settings=true"*) echo "{}"; return 0 ;;
        esac
        return 1
      }
      clear_stale_allocation_exclusion_for_self
      rc=$?
      [ ! -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_REMOVED"
      exit $rc
    '
    The status should be success
    The output should include "no shard allocation exclusion set"
    The output should include "MARKER_REMOVED"
  End
End
