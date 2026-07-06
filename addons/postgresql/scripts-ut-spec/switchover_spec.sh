# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "PostgreSQL Switchover Script Tests"

  Include ../scripts/switchover.sh
  Include $common_library_file

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  setup() {
    tmpdir=$(mktemp -d -t pg-switchover-XXXXXX)
    STATE_FILE="${tmpdir}/switchover-sent"
    CLUSTER_JSON_BEFORE='{"members":[{"name":"pod-0","role":"leader"},{"name":"pod-1","role":"replica"}]}'
    CLUSTER_JSON_AFTER='{"members":[{"name":"pod-0","role":"replica"},{"name":"pod-1","role":"leader"}]}'
    SWITCHOVER_BODY="Successfully switched over"
    SWITCHOVER_CODE=200
    CURL_CLUSTER_EXIT=0
    CURL_SWITCHOVER_EXIT=0
    SWITCHOVER_VERIFY_ATTEMPTS=2
    SWITCHOVER_VERIFY_INTERVAL=0
    export STATE_FILE CLUSTER_JSON_BEFORE CLUSTER_JSON_AFTER SWITCHOVER_BODY \
      SWITCHOVER_CODE CURL_CLUSTER_EXIT CURL_SWITCHOVER_EXIT \
      SWITCHOVER_VERIFY_ATTEMPTS SWITCHOVER_VERIFY_INTERVAL
    unset KB_SWITCHOVER_CANDIDATE_NAME 2>/dev/null || true
  }

  teardown() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'teardown'

  # Emulates the two curl call shapes in switchover.sh:
  #   GET  .../cluster    -> cluster topology JSON (switches once /switchover was called)
  #   POST .../switchover -> "<body>\n<http_code>" (the -w "\n%{http_code}" format)
  Mock curl
    url=""
    for arg; do url="$arg"; done
    case "$url" in
      */cluster)
        if [ "${CURL_CLUSTER_EXIT:-0}" -ne 0 ]; then
          exit "${CURL_CLUSTER_EXIT}"
        fi
        if [ -f "${STATE_FILE}" ]; then
          printf '%s' "${CLUSTER_JSON_AFTER}"
        else
          printf '%s' "${CLUSTER_JSON_BEFORE}"
        fi
        ;;
      */switchover)
        if [ "${CURL_SWITCHOVER_EXIT:-0}" -ne 0 ]; then
          exit "${CURL_SWITCHOVER_EXIT}"
        fi
        touch "${STATE_FILE}"
        printf '%s\n%s' "${SWITCHOVER_BODY}" "${SWITCHOVER_CODE}"
        ;;
    esac
  End

  Describe "switchover()"
    Context "when CURRENT_POD_NAME is not set"
      It "exits with an error"
        unset CURRENT_POD_NAME
        When run switchover
        The output should include "CURRENT_POD_NAME is not set. Exiting..."
        The status should be failure
      End
    End

    Context "when the leader cannot be resolved from patroni"
      It "defers with a transient classification instead of silently succeeding"
        export CURRENT_POD_NAME="pod-0"
        export CURL_CLUSTER_EXIT=7
        When run switchover
        The status should be failure
        The error should include "phase: leader-not-resolved"
        The error should include "next-retry-safe: yes"
      End
    End

    Context "when the current pod is no longer the leader"
      It "reports success without candidate when leadership already moved"
        export CURRENT_POD_NAME="pod-1"
        When run switchover
        The status should eq 0
        The output should include "Leadership already moved to pod-0"
      End

      It "reports success when the requested candidate is already the leader"
        export CURRENT_POD_NAME="pod-1"
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-0"
        When run switchover
        The status should eq 0
        The output should include "Switchover already completed"
      End

      It "fails when the leader is neither this pod nor the candidate"
        export CURRENT_POD_NAME="pod-1"
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-2"
        When run switchover
        The status should be failure
        The error should include "phase: leader-mismatch"
        The error should include "next-retry-safe: no"
      End
    End

    Context "when the switchover is performed"
      It "succeeds with candidate and verifies the new leader"
        export CURRENT_POD_NAME="pod-0"
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-1"
        When run switchover
        The status should eq 0
        The output should include "Switchover API response (HTTP 200)"
        The output should include "Switchover verified: new leader is pod-1"
      End

      It "succeeds without candidate once leadership leaves the old leader"
        export CURRENT_POD_NAME="pod-0"
        When run switchover
        The status should eq 0
        The output should include "Switchover verified: new leader is pod-1"
      End

      It "verifies a standby_leader in standby clusters"
        export CURRENT_POD_NAME="pod-0"
        export CLUSTER_JSON_BEFORE='{"members":[{"name":"pod-0","role":"standby_leader"},{"name":"pod-1","role":"replica"}]}'
        export CLUSTER_JSON_AFTER='{"members":[{"name":"pod-0","role":"replica"},{"name":"pod-1","role":"standby_leader"}]}'
        When run switchover
        The status should eq 0
        The output should include "Switchover verified: new leader is pod-1"
      End
    End

    Context "when patroni rejects or fails the switchover request"
      It "defers with a transient classification on HTTP 503"
        export CURRENT_POD_NAME="pod-0"
        export SWITCHOVER_CODE=503
        export SWITCHOVER_BODY="switchover is not possible: no good candidates"
        When run switchover
        The status should be failure
        The output should include "Switchover API response (HTTP 503)"
        The error should include "phase: switchover-rejected"
        The error should include "next-retry-safe: yes"
      End

      It "fails hard on HTTP 412"
        export CURRENT_POD_NAME="pod-0"
        export SWITCHOVER_CODE=412
        export SWITCHOVER_BODY="switchover is not possible: leader name does not match"
        When run switchover
        The status should be failure
        The output should include "Switchover API response (HTTP 412)"
        The error should include "phase: switchover-rejected"
        The error should include "next-retry-safe: no"
      End

      It "fails when the switchover API is unreachable"
        export CURRENT_POD_NAME="pod-0"
        export CURL_SWITCHOVER_EXIT=7
        When run switchover
        The status should be failure
        The output should include "performs switchover without candidate"
        The error should include "phase: switchover-api-unreachable"
        The error should include "next-retry-safe: yes"
      End
    End

    Context "when the switchover result cannot be confirmed"
      It "defers when the leader does not change within the bounded window"
        export CURRENT_POD_NAME="pod-0"
        export CLUSTER_JSON_AFTER="${CLUSTER_JSON_BEFORE}"
        When run switchover
        The status should be failure
        The output should include "Switchover not confirmed yet"
        The error should include "phase: switchover-not-confirmed"
        The error should include "next-retry-safe: yes"
      End

      It "fails hard when leadership moved to a pod other than the candidate"
        export CURRENT_POD_NAME="pod-0"
        export KB_SWITCHOVER_CANDIDATE_NAME="pod-1"
        export CLUSTER_JSON_AFTER='{"members":[{"name":"pod-0","role":"replica"},{"name":"pod-2","role":"leader"}]}'
        When run switchover
        The status should be failure
        The output should include "Switchover API response (HTTP 200)"
        The error should include "phase: switchover-wrong-leader"
        The error should include "next-retry-safe: no"
      End
    End
  End
End
