# shellcheck shell=bash

Describe "MongoDB switchover lifecycle contract"

  run_switchover() {
    local role="$1"
    local current_name="$2"
    local candidate_name="$3"
    local syncer_rc="${4:-0}"
    local timeout_mode="${5:-run}"
    local chart_dir
    local script
    local temp_dir
    local original_path
    local rc

    chart_dir=$(cd .. && pwd)
    script="$chart_dir/scripts/mongodb-switchover.sh"
    temp_dir=$(mktemp -d)
    original_path="$PATH"

    mkdir -p "$temp_dir/bin"
    cat > "$temp_dir/bin/syncerctl" <<'MOCK'
#!/usr/bin/env bash
printf 'SYNCERCTL' >> "$MOCK_CALL_LOG"
printf ' <%s>' "$@" >> "$MOCK_CALL_LOG"
printf '\n' >> "$MOCK_CALL_LOG"
printf '%s\n' "${MOCK_SYNCER_STDOUT:-switchover success}"
if [[ "${MOCK_SYNCER_RC:-0}" -ne 0 ]]; then
  printf '%s' "${MOCK_SYNCER_STDERR:-}" >&2
fi
exit "${MOCK_SYNCER_RC:-0}"
MOCK
    cat > "$temp_dir/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
printf 'TIMEOUT <%s>\n' "$1" >> "$MOCK_CALL_LOG"
shift
if [[ "${MOCK_TIMEOUT_MODE:-run}" == "expire" ]]; then
  exit 124
fi
exec "$@"
MOCK
    chmod +x "$temp_dir/bin/syncerctl" "$temp_dir/bin/timeout"

    export MOCK_CALL_LOG="$temp_dir/calls.log"
    : > "$MOCK_CALL_LOG"
    export MOCK_SYNCER_RC="$syncer_rc"
    export MOCK_SYNCER_STDOUT="switchover success"
    export MOCK_SYNCER_STDERR="syncer failure detail"
    export MOCK_TIMEOUT_MODE="$timeout_mode"
    export MONGODB_SYNCERCTL_BIN="$temp_dir/bin/syncerctl"
    export PATH="$temp_dir/bin:$PATH"
    export KB_SWITCHOVER_ROLE="$role"
    export KB_SWITCHOVER_CURRENT_NAME="$current_name"
    export KB_SWITCHOVER_CANDIDATE_NAME="$candidate_name"

    bash "$script"
    rc=$?
    printf 'TEST:calls='
    paste -sd, "$MOCK_CALL_LOG"

    PATH="$original_path"
    unset MONGODB_SYNCERCTL_BIN
    rm -rf "$temp_dir"
    return "$rc"
  }

  verify_rendered_switchover_actions() {
    local chart_dir

    chart_dir=$(cd .. && pwd)
    # shellcheck disable=SC2016
    helm template kb-addon-mongodb "$chart_dir" --dependency-update | ruby -ryaml -e '
      documents = YAML.load_stream($stdin.read).compact
      actions = documents.each_with_object([]) do |document, matches|
        next unless document["kind"] == "ComponentDefinition"
        action = document.dig("spec", "lifecycleActions", "switchover")
        matches << [document.dig("metadata", "name"), action] if action
      end

      abort "expected three switchover actions, got #{actions.length}" unless actions.length == 3
      actions.each do |name, action|
        timeout = action["timeoutSeconds"]
        abort "#{name}: expected timeoutSeconds=30, got #{timeout.inspect}" unless timeout == 30

        command = action.dig("exec", "command")
        abort "#{name}: malformed command #{command.inspect}" unless command&.length == 3
        abort "#{name}: expected /bin/sh -c" unless command[0, 2] == ["/bin/sh", "-c"]

        body = command[2]
        expected = "/scripts/mongodb-switchover.sh > /tmp/switchover.log"
        abort "#{name}: unexpected command #{body.inspect}" unless body == expected
        abort "#{name}: stderr must remain visible to kbagent" if body.include?("2>&1")
      end
    '
  }

  It "executes one bounded candidate switchover with exact argv"
    When call run_switchover primary mongodb-0 mongodb-1
    The status should be success
    The output should include "switchover success"
    The output should include "TEST:calls=TIMEOUT <20s>,SYNCERCTL <switchover> <--primary> <mongodb-0> <--candidate> <mongodb-1>"
  End

  It "executes one bounded candidate-free switchover with exact argv"
    When call run_switchover primary mongodb-0 ""
    The status should be success
    The output should include "TEST:calls=TIMEOUT <20s>,SYNCERCTL <switchover> <--primary> <mongodb-0>"
    The output should not include "<--candidate>"
  End

  It "returns a clean no-op for the declared secondary role"
    When call run_switchover secondary mongodb-1 mongodb-0
    The status should be success
    The output should include "role=secondary does not require transfer"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
  End

  It "rejects an empty role before invoking syncerctl"
    When call run_switchover "" mongodb-0 mongodb-1
    The status should equal 2
    The stderr should include "phase: invalid-role"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
  End

  It "rejects an unknown role before invoking syncerctl"
    When call run_switchover arbiter mongodb-0 mongodb-1
    The status should equal 2
    The stderr should include "phase: invalid-role"
    The stderr should include "observed-role: arbiter"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
  End

  It "rejects a missing current pod before invoking syncerctl"
    When call run_switchover primary "" mongodb-1
    The status should equal 2
    The stderr should include "phase: missing-current-pod"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
  End

  It "preserves a syncerctl failure status and classifies it"
    When call run_switchover primary mongodb-0 mongodb-1 23
    The status should equal 23
    The stderr should include "syncer failure detail"
    The stderr should include "phase: syncerctl-failed"
    The stderr should include "syncerctl-rc: 23"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls=TIMEOUT <20s>,SYNCERCTL <switchover> <--primary> <mongodb-0> <--candidate> <mongodb-1>"
  End

  It "preserves timeout status 124 and classifies uncertain completion"
    When call run_switchover primary mongodb-0 mongodb-1 0 expire
    The status should equal 124
    The stderr should include "phase: syncerctl-timeout"
    The stderr should include "syncerctl-rc: 124"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls=TIMEOUT <20s>"
    The output should not include "SYNCERCTL"
  End

  It "renders all three actions with a 30 second ceiling and visible stderr"
    When call verify_rendered_switchover_actions
    The status should be success
  End
End
