# shellcheck shell=bash

Describe "MongoDB switchover lifecycle contract"

  run_switchover() {
    local role="$1"
    local current_name="$2"
    local candidate_name="$3"
    local syncer_rc="${4:-0}"
    local timeout_mode="${5:-run}"
    local kubectl_mode="${6:-pending-then-absent}"
    local namespace="${7-test-ns}"
    local cluster_component_name="${8-mongo-rs}"
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
#!/bin/sh
printf 'SYNCERCTL' >> "$MOCK_CALL_LOG"
printf ' <%s>' "$@" >> "$MOCK_CALL_LOG"
printf '\n' >> "$MOCK_CALL_LOG"
printf '%s\n' "${MOCK_SYNCER_STDOUT:-switchover accepted}"
if [ "${MOCK_SYNCER_RC:-0}" -ne 0 ]; then
  printf '%s' "${MOCK_SYNCER_STDERR:-}" >&2
fi
exit "${MOCK_SYNCER_RC:-0}"
MOCK
    cat > "$temp_dir/bin/kubectl" <<'MOCK'
#!/bin/sh
printf 'KUBECTL' >> "$MOCK_CALL_LOG"
printf ' <%s>' "$@" >> "$MOCK_CALL_LOG"
printf '\n' >> "$MOCK_CALL_LOG"

count=$(cat "$MOCK_KUBECTL_COUNT")
count=$((count + 1))
printf '%s\n' "$count" > "$MOCK_KUBECTL_COUNT"

case "${MOCK_KUBECTL_MODE:-pending-then-absent}" in
  pending-then-absent)
    if [ "$count" -eq 1 ]; then
      printf 'configmap/%s-switchover\n' "$KB_CLUSTER_COMP_NAME"
    fi
    ;;
  immediate-absent)
    ;;
  always-pending)
    printf 'configmap/%s-switchover\n' "$KB_CLUSTER_COMP_NAME"
    ;;
  failure)
    printf 'kubernetes api failure detail\n' >&2
    exit 19
    ;;
  malformed)
    printf 'configmap/unexpected-switchover\n'
    ;;
  *)
    printf 'mock configuration error: %s\n' "$MOCK_KUBECTL_MODE" >&2
    exit 98
    ;;
esac
MOCK
    cat > "$temp_dir/bin/timeout" <<'MOCK'
#!/bin/sh
printf 'TIMEOUT <%s>\n' "$1" >> "$MOCK_CALL_LOG"
case "${MOCK_TIMEOUT_MODE:-run}:$1" in
  syncer-expire:10s|probe-expire:3s)
    exit 124
    ;;
esac
shift
exec "$@"
MOCK
    cat > "$temp_dir/bin/sleep" <<'MOCK'
#!/bin/sh
printf 'SLEEP <%s>\n' "$1" >> "$MOCK_CALL_LOG"
MOCK
    chmod +x \
      "$temp_dir/bin/syncerctl" \
      "$temp_dir/bin/kubectl" \
      "$temp_dir/bin/timeout" \
      "$temp_dir/bin/sleep"

    export MOCK_CALL_LOG="$temp_dir/calls.log"
    export MOCK_KUBECTL_COUNT="$temp_dir/kubectl-count"
    : > "$MOCK_CALL_LOG"
    printf '0\n' > "$MOCK_KUBECTL_COUNT"
    export MOCK_SYNCER_RC="$syncer_rc"
    export MOCK_SYNCER_STDOUT="switchover accepted"
    export MOCK_SYNCER_STDERR="syncer failure detail"
    export MOCK_TIMEOUT_MODE="$timeout_mode"
    export MOCK_KUBECTL_MODE="$kubectl_mode"
    export MONGODB_SYNCERCTL_BIN="$temp_dir/bin/syncerctl"
    export MONGODB_KUBECTL_BIN="$temp_dir/bin/kubectl"
    export PATH="$temp_dir/bin:$PATH"
    export KB_SWITCHOVER_ROLE="$role"
    export KB_SWITCHOVER_CURRENT_NAME="$current_name"
    export KB_SWITCHOVER_CANDIDATE_NAME="$candidate_name"
    export CLUSTER_NAMESPACE="$namespace"
    export KB_CLUSTER_COMP_NAME="$cluster_component_name"

    sh "$script"
    rc=$?
    printf 'TEST:calls='
    paste -sd, "$MOCK_CALL_LOG"

    PATH="$original_path"
    unset MONGODB_SYNCERCTL_BIN MONGODB_KUBECTL_BIN
    rm -rf "$temp_dir"
    return "$rc"
  }

  verify_rendered_switchover_actions_for_path() {
    local chart_dir="$1"
    local expected_data_path="$2"
    shift 2
    # shellcheck disable=SC2016
    helm template kb-addon-mongodb "$chart_dir" --dependency-update "$@" |
      EXPECTED_DATA_PATH="$expected_data_path" ruby -ryaml -e '
      expected_data_path = ENV.fetch("EXPECTED_DATA_PATH")
      documents = YAML.load_stream($stdin.read).compact
      components = documents.select do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("spec", "lifecycleActions", "switchover")
      end

      abort "expected three switchover actions, got #{components.length}" unless components.length == 3
      components.each do |component|
        name = component.dig("metadata", "name")
        action = component.dig("spec", "lifecycleActions", "switchover")
        timeout = action["timeoutSeconds"]
        abort "#{name}: expected timeoutSeconds=50, got #{timeout.inspect}" unless timeout == 50

        command = action.dig("exec", "command")
        abort "#{name}: malformed command #{command.inspect}" unless command&.length == 3
        abort "#{name}: expected /bin/sh -c" unless command[0, 2] == ["/bin/sh", "-c"]
        abort "#{name}: unexpected action image" if action.dig("exec", "image")
        unless action.dig("exec", "container") == "mongodb"
          abort "#{name}: switchover must select the mongodb container"
        end

        body = command[2]
        expected = "/scripts/mongodb-switchover.sh > /tmp/switchover.log"
        abort "#{name}: unexpected command #{body.inspect}" unless body == expected
        abort "#{name}: stderr must remain visible to kbagent" if body.include?("2>&1")
        kubectl_env = Array(action.dig("exec", "env")).find do |item|
          item["name"] == "MONGODB_KUBECTL_BIN"
        end
        unless kubectl_env == {
          "name" => "MONGODB_KUBECTL_BIN",
          "value" => "#{expected_data_path}/tmp/bin/kubectl"
        }
          abort "#{name}: missing exact MONGODB_KUBECTL_BIN env"
        end

        vars = component.dig("spec", "vars") || []
        %w[CLUSTER_NAMESPACE KB_CLUSTER_COMP_NAME].each do |required|
          variable = vars.find { |item| item["name"] == required }
          abort "#{name}: missing required var #{required}" unless variable
        end

        init = (component.dig("spec", "runtime", "initContainers") || [])
          .find { |container| container["name"] == "init-kubectl" }
        abort "#{name}: missing init-kubectl" unless init

        mongodb = (component.dig("spec", "runtime", "containers") || [])
          .find { |container| container["name"] == "mongodb" }
        abort "#{name}: missing selected mongodb runtime container" unless mongodb
        mounts = Array(mongodb["volumeMounts"])
        script_mount = mounts.find { |mount| mount["mountPath"] == "/scripts" }
        abort "#{name}: selected container does not share /scripts" unless script_mount
        tools_mount = mounts.find { |mount| mount["mountPath"] == "/tools" }
        abort "#{name}: selected container does not share /tools" unless tools_mount
        data_mount = mounts.find { |mount| mount["mountPath"] == expected_data_path }
        abort "#{name}: selected container missing #{expected_data_path}" unless data_mount

        init_data_mount = Array(init["volumeMounts"]).find do |mount|
          mount["name"] == data_mount["name"] &&
            mount["mountPath"] == expected_data_path
        end
        abort "#{name}: init and mongodb data mounts do not match" unless init_data_mount

        init_body = Array(init["command"]).join("\n")
        unless init_body.include?("/opt/bitnami/kubectl/bin/kubectl") &&
               init_body.include?("#{expected_data_path}/tmp/bin")
          abort "#{name}: init-kubectl does not project the expected binary"
        end

        configmaps = (component.dig("spec", "policyRules") || []).find do |rule|
          rule["apiGroups"] == [""] && Array(rule["resources"]).include?("configmaps")
        end
        abort "#{name}: missing ConfigMap policy rule" unless configmaps
        abort "#{name}: ConfigMap get permission missing" unless Array(configmaps["verbs"]).include?("get")
      end
    '
  }

  verify_rendered_switchover_actions() {
    local chart_dir

    chart_dir=$(cd .. && pwd)
    verify_rendered_switchover_actions_for_path "$chart_dir" "/data/mongodb" || return
    verify_rendered_switchover_actions_for_path \
      "$chart_dir" \
      "/custom/mongodb-data" \
      --set dataMountPath=/custom/mongodb-data
  }

  verify_posix_action_source() {
    local chart_dir
    local script

    chart_dir=$(cd .. && pwd)
    script="$chart_dir/scripts/mongodb-switchover.sh"
    [ "$(sed -n '1p' "$script")" = "#!/bin/sh" ] || return 1
    sh -n "$script" || return
    shellcheck --shell=sh --severity=warning "$script"
  }

  It "closes a candidate switchover only after the exact completion ConfigMap disappears"
    When call run_switchover primary mongodb-0 mongodb-1
    The status should be success
    The output should include "switchover accepted"
    The output should include "phase: completed"
    The output should include "completion-configmap: mongo-rs-switchover"
    The output should include "TEST:calls=TIMEOUT <10s>,SYNCERCTL <switchover> <--primary> <mongodb-0> <--candidate> <mongodb-1>,TIMEOUT <3s>,KUBECTL <--request-timeout=2s> <--namespace> <test-ns> <get> <configmap> <mongo-rs-switchover> <--ignore-not-found> <-o> <name>,SLEEP <2>,TIMEOUT <3s>,KUBECTL <--request-timeout=2s> <--namespace> <test-ns> <get> <configmap> <mongo-rs-switchover> <--ignore-not-found> <-o> <name>"
  End

  It "closes a candidate-free switchover only after the exact completion ConfigMap disappears"
    When call run_switchover primary mongodb-0 ""
    The status should be success
    The output should include "phase: completed"
    The output should include "completion-configmap: mongo-rs-switchover"
    The output should include "TEST:calls=TIMEOUT <10s>,SYNCERCTL <switchover> <--primary> <mongodb-0>,TIMEOUT <3s>,KUBECTL"
    The output should not include "<--candidate>"
  End

  It "accepts immediate ConfigMap absence after a successful request as completed"
    When call run_switchover primary mongodb-0 mongodb-1 0 run immediate-absent
    The status should be success
    The output should include "phase: completed"
    The output should include "TEST:calls=TIMEOUT <10s>,SYNCERCTL <switchover> <--primary> <mongodb-0> <--candidate> <mongodb-1>,TIMEOUT <3s>,KUBECTL"
    The output should not include "SLEEP"
  End

  It "fails closed after six bounded probes while the completion ConfigMap remains"
    When call run_switchover primary mongodb-0 mongodb-1 0 run always-pending
    The status should equal 1
    The stderr should include "phase: completion-not-observed"
    The stderr should include "completion-configmap: mongo-rs-switchover"
    The stderr should include "completion-probes: 6"
    The stderr should include "next-retry-safe: no"
    The output should include "SLEEP <2>,TIMEOUT <3s>,KUBECTL"
    The output should include "TEST:calls=TIMEOUT <10s>,SYNCERCTL"
  End

  It "preserves a completion-probe failure and classifies it"
    When call run_switchover primary mongodb-0 mongodb-1 0 run failure
    The status should equal 19
    The stderr should include "kubernetes api failure detail"
    The stderr should include "phase: completion-probe-failed"
    The stderr should include "completion-probe-rc: 19"
    The stderr should include "next-retry-safe: no"
    The output should not include "SLEEP"
  End

  It "preserves a completion-probe timeout and classifies it"
    When call run_switchover primary mongodb-0 mongodb-1 0 probe-expire
    The status should equal 124
    The stderr should include "phase: completion-probe-timeout"
    The stderr should include "completion-probe-rc: 124"
    The stderr should include "next-retry-safe: no"
    The output should not include "KUBECTL"
    The output should not include "SLEEP"
  End

  It "rejects malformed completion-probe output"
    When call run_switchover primary mongodb-0 mongodb-1 0 run malformed
    The status should equal 1
    The stderr should include "phase: malformed-completion-probe"
    The stderr should include "observed-output: configmap/unexpected-switchover"
    The stderr should include "next-retry-safe: no"
    The output should not include "SLEEP"
  End

  It "returns a clean no-op for the declared secondary role"
    When call run_switchover secondary mongodb-1 mongodb-0
    The status should be success
    The output should include "role=secondary does not require transfer"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "rejects an empty role before invoking tools"
    When call run_switchover "" mongodb-0 mongodb-1
    The status should equal 2
    The stderr should include "phase: invalid-role"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "rejects an unknown role before invoking tools"
    When call run_switchover arbiter mongodb-0 mongodb-1
    The status should equal 2
    The stderr should include "phase: invalid-role"
    The stderr should include "observed-role: arbiter"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "rejects a missing current pod before invoking tools"
    When call run_switchover primary "" mongodb-1
    The status should equal 2
    The stderr should include "phase: missing-current-pod"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls="
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "rejects a missing namespace before invoking tools"
    When call run_switchover primary mongodb-0 mongodb-1 0 run pending-then-absent ""
    The status should equal 2
    The stderr should include "phase: missing-cluster-namespace"
    The stderr should include "next-retry-safe: no"
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "rejects a missing cluster-component identity before invoking tools"
    When call run_switchover primary mongodb-0 mongodb-1 0 run pending-then-absent test-ns ""
    The status should equal 2
    The stderr should include "phase: missing-cluster-component-name"
    The stderr should include "next-retry-safe: no"
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "preserves a syncerctl failure and does not infer success from ConfigMap absence"
    When call run_switchover primary mongodb-0 mongodb-1 23
    The status should equal 23
    The stderr should include "syncer failure detail"
    The stderr should include "phase: syncerctl-failed"
    The stderr should include "syncerctl-rc: 23"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls=TIMEOUT <10s>,SYNCERCTL <switchover> <--primary> <mongodb-0> <--candidate> <mongodb-1>"
    The output should not include "KUBECTL"
  End

  It "preserves syncerctl timeout status and does not probe ambiguous absence"
    When call run_switchover primary mongodb-0 mongodb-1 0 syncer-expire
    The status should equal 124
    The stderr should include "phase: syncerctl-timeout"
    The stderr should include "syncerctl-rc: 124"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls=TIMEOUT <10s>"
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "declares and passes the POSIX sh action-source gate"
    When call verify_posix_action_source
    The status should be success
  End

  It "renders all three actions with the completion-observation prerequisites"
    When call verify_rendered_switchover_actions
    The status should be success
  End
End
