# shellcheck shell=bash

if ! validate_shell_type_and_version "bash" 3 &>/dev/null; then
  echo "redis_syncer_switchover_spec.sh skips all cases because bash 3 or higher is not installed."
  exit 0
fi

Describe 'redis-syncer-switchover.sh'
  script='../scripts/redis-syncer-switchover.sh'
  fixture_dir="${SHELLSPEC_TMPBASE}/redis-syncer-switchover"

  setup() {
    mkdir -p "$fixture_dir"
    cat >"$fixture_dir/timeout" <<'MOCK'
#!/bin/bash
printf '<%s>\n' "$@"
if [[ -n "${MOCK_ERROR:-}" ]]; then
  printf '%s\n' "$MOCK_ERROR" >&2
fi
exit "${MOCK_STATUS:-0}"
MOCK
    chmod +x "$fixture_dir/timeout"
    export PATH="$fixture_dir:$PATH"
    export KB_SWITCHOVER_CURRENT_NAME='redis-0'
    unset KB_SWITCHOVER_CANDIDATE_NAME MOCK_STATUS MOCK_ERROR
  }
  BeforeEach 'setup'

  It 'submits a bounded request without an unset candidate'
    When run bash "$script"
    The status should be success
    The output should eq "<-k>
<5>
<50>
</tools/syncerctl>
<switchover>
<--primary>
<redis-0>"
    The stderr should be blank
  End

  It 'omits an explicitly empty candidate'
    export KB_SWITCHOVER_CANDIDATE_NAME=''
    When run bash "$script"
    The status should be success
    The output should not include '<--candidate>'
    The stderr should be blank
  End

  It 'passes the candidate as one argument'
    export KB_SWITCHOVER_CANDIDATE_NAME='redis-1 --force'
    When run bash "$script"
    The status should be success
    The output should include '<--candidate>'
    The output should include '<redis-1 --force>'
    The stderr should be blank
  End

  It 'rejects a missing current primary before issuing a request'
    unset KB_SWITCHOVER_CURRENT_NAME
    When run bash "$script"
    The status should eq 2
    The output should be blank
    The stderr should eq 'KB_SWITCHOVER_CURRENT_NAME is required'
  End

  It 'preserves the request failure and diagnostic'
    export MOCK_STATUS=23 MOCK_ERROR='candidate is unhealthy'
    When run bash "$script"
    The status should eq 23
    The output should include '<switchover>'
    The stderr should eq 'candidate is unhealthy'
  End

  Parameters
    124
    137
  End
  It 'reports timeout as an uncertain request outcome'
    export MOCK_STATUS="$1"
    When run bash "$script"
    The status should eq "$1"
    The output should include '<switchover>'
    The stderr should include 'check DCS and roles before retrying'
    The stderr should include 'may already be accepted'
  End
End
