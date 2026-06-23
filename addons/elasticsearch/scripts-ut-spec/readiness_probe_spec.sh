# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Elasticsearch readiness probe stale exclusion cleanup"
  setup() { rm -f /tmp/stale-exclusion-cleanup.pending /tmp/shellspec_put_done; }
  cleanup() { rm -f /tmp/stale-exclusion-cleanup.pending /tmp/shellspec_put_done; }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "clears stale exclusion, removes marker, returns Ready"
    When run bash -c '
      touch /tmp/stale-exclusion-cleanup.pending
      rm -f /tmp/shellspec_put_done
      export ES_READINESS_PROBE_UNIT_TEST=1
      export POD_NAME=es-ops-data-2
      export POD_IP=127.0.0.1
      export TLS_ENABLED=false
      export ELASTIC_USER_PASSWORD=test-pass
      export READINESS_PROBE_PROTOCOL=http
      LOOPBACK=127.0.0.1
      BASIC_AUTH="-u elastic:test-pass"
      . ../scripts/readiness-probe-script.sh
      curl() {
        case "$*" in
          *"_cluster/settings?include_defaults=false&flat_settings=true"*)
            if [ -f /tmp/shellspec_put_done ]; then
              echo "{}"
            else
              echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-2\"}"
            fi
            return 0
            ;;
          *"_cluster/settings"*) touch /tmp/shellspec_put_done; return 0 ;;
        esac
        return 1
      }
      try_readiness_cleanup_stale_exclusion
      rc=$?
      rm -f /tmp/shellspec_put_done
      [ ! -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_REMOVED"
      exit $rc
    '
    The status should be success
    The output should include "stale exclusion cleared for es-ops-data-2"
    The output should include "MARKER_REMOVED"
  End

  It "keeps marker and returns NotReady when PUT fails"
    When run bash -c '
      touch /tmp/stale-exclusion-cleanup.pending
      export ES_READINESS_PROBE_UNIT_TEST=1
      export POD_NAME=es-ops-data-2
      export POD_IP=127.0.0.1
      export TLS_ENABLED=false
      export ELASTIC_USER_PASSWORD=test-pass
      export READINESS_PROBE_PROTOCOL=http
      LOOPBACK=127.0.0.1
      BASIC_AUTH="-u elastic:test-pass"
      . ../scripts/readiness-probe-script.sh
      curl() {
        case "$*" in
          *"_cluster/settings?include_defaults=false&flat_settings=true"*)
            echo "{\"persistent.cluster.routing.allocation.exclude._name\":\"es-ops-data-2\"}"
            return 0
            ;;
          *"_cluster/settings"*) return 22 ;;
        esac
        return 1
      }
      try_readiness_cleanup_stale_exclusion
      rc=$?
      [ -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_KEPT"
      exit $rc
    '
    The status should be failure
    The output should include "MARKER_KEPT"
    The error should include "PUT clear failed"
  End

  It "removes marker and returns Ready when no stale exclusion exists"
    When run bash -c '
      touch /tmp/stale-exclusion-cleanup.pending
      export ES_READINESS_PROBE_UNIT_TEST=1
      export POD_NAME=es-ops-data-2
      export POD_IP=127.0.0.1
      export TLS_ENABLED=false
      export ELASTIC_USER_PASSWORD=test-pass
      export READINESS_PROBE_PROTOCOL=http
      LOOPBACK=127.0.0.1
      BASIC_AUTH="-u elastic:test-pass"
      . ../scripts/readiness-probe-script.sh
      curl() {
        case "$*" in
          *"_cluster/settings?include_defaults=false&flat_settings=true"*)
            echo "{}"
            return 0
            ;;
        esac
        return 1
      }
      try_readiness_cleanup_stale_exclusion
      rc=$?
      [ ! -f /tmp/stale-exclusion-cleanup.pending ] && echo "MARKER_REMOVED"
      exit $rc
    '
    The status should be success
    The output should include "no stale exclusion for es-ops-data-2"
    The output should include "MARKER_REMOVED"
  End
End
