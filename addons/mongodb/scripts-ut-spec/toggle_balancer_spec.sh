# shellcheck shell=bash

Describe "MongoDB toggle-balancer operation contract"

  render_toggle_balancer_script() {
    local output_file="$1"
    local chart_dir

    chart_dir=$(cd .. && pwd)
    # shellcheck disable=SC2016
    helm template kb-addon-mongodb "$chart_dir" --dependency-update | ruby -ryaml -e '
      documents = YAML.load_stream($stdin.read).compact
      matches = documents.select do |document|
        document["kind"] == "OpsDefinition" &&
          document.dig("metadata", "name") == "mongodb-shard-toggle-balancer"
      end
      abort "expected one toggle-balancer OpsDefinition, got #{matches.length}" unless matches.length == 1

      action = matches.first.fetch("spec").fetch("actions").find do |candidate|
        candidate["name"] == "toggle-balancer"
      end
      abort "toggle-balancer action is missing" unless action

      command = action.dig("exec", "command", 2)
      abort "toggle-balancer shell command is missing" unless command.is_a?(String)
      print command
    ' > "$output_file"
  }

  run_toggle_balancer() {
    local parameter_mode="$1"
    local observed_state="$2"
    local action_rc="$3"
    local state_rc="${4:-0}"
    local temp_dir
    local script_file

    temp_dir=$(mktemp -d)
    script_file="$temp_dir/toggle-balancer.sh"
    render_toggle_balancer_script "$script_file" || return 1

    mkdir -p "$temp_dir/bin"
    cat > "$temp_dir/bin/whereis" <<'MOCK'
#!/usr/bin/env bash
echo "mongosh: ${MOCK_BIN_DIR}/mongosh"
MOCK
    cat > "$temp_dir/bin/mongosh" <<'MOCK'
#!/usr/bin/env bash
query=""
for argument in "$@"; do
  query="$argument"
done

case "$query" in
  *ping*)
    echo '{ ok: 1 }'
    ;;
  *sh.startBalancer*)
    echo 'ACTION:start'
    exit "$MOCK_ACTION_RC"
    ;;
  *sh.stopBalancer*)
    echo 'ACTION:stop'
    exit "$MOCK_ACTION_RC"
    ;;
  *sh.getBalancerState*)
    echo "$MOCK_BALANCER_STATE"
    exit "$MOCK_STATE_RC"
    ;;
  *)
    echo "unexpected query: $query" >&2
    exit 64
    ;;
esac
MOCK
    chmod +x "$temp_dir/bin/whereis" "$temp_dir/bin/mongosh"

    export MOCK_BIN_DIR="$temp_dir/bin"
    export MOCK_BALANCER_STATE="$observed_state"
    export MOCK_ACTION_RC="$action_rc"
    export MOCK_STATE_RC="$state_rc"
    export SERVICE_PORT=27017
    export MONGODB_ROOT_USER=root
    export MONGODB_ROOT_PASSWORD=password
    export PATH="$temp_dir/bin:$PATH"

    if [[ "$parameter_mode" == "omitted" ]]; then
      unset enableBalancer
    else
      export enableBalancer="$parameter_mode"
    fi

    bash "$script_file"
    local rc=$?
    rm -rf "$temp_dir"
    return "$rc"
  }

  It "starts the balancer when enableBalancer is omitted"
    When call run_toggle_balancer omitted true 0
    The status should be success
    The output should include "ACTION:start"
    The output should include "INFO: Balancer is enabled."
    The output should not include "ACTION:stop"
  End

  It "stops the balancer when enableBalancer is false"
    When call run_toggle_balancer false false 0
    The status should be success
    The output should include "ACTION:stop"
    The output should include "INFO: Balancer is disabled."
    The output should not include "ACTION:start"
  End

  It "propagates a balancer command failure"
    When call run_toggle_balancer true true 17
    The status should equal 17
    The output should include "ACTION:start"
    The stderr should include "ERROR: Balancer command failed with exit code 17."
    The output should not include "INFO: Balancer is enabled."
  End

  It "fails when the observed balancer state does not match the request"
    When call run_toggle_balancer true false 0
    The status should be failure
    The output should include "ACTION:start"
    The stderr should include "ERROR: Balancer state verification failed"
    The output should not include "INFO: Balancer is enabled."
  End

  It "rejects an invalid parameter before changing the balancer"
    When call run_toggle_balancer yes false 0
    The status should equal 2
    The stderr should include "ERROR: Invalid enableBalancer value: yes"
    The output should not include "ACTION:"
  End

  It "propagates a balancer state query failure"
    When call run_toggle_balancer true true 0 19
    The status should equal 19
    The output should include "ACTION:start"
    The stderr should include "ERROR: Failed to read balancer state with exit code 19."
    The output should not include "INFO: Balancer is enabled."
  End
End
