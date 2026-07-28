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
  syncer-expire-143:10s|probe-expire-143:3s)
    exit 143
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
    if [ -n "$candidate_name" ]; then
      export KB_SWITCHOVER_CANDIDATE_NAME="$candidate_name"
      export KB_SWITCHOVER_CANDIDATE_FQDN="$candidate_name.test-ns.svc"
    else
      unset KB_SWITCHOVER_CANDIDATE_NAME KB_SWITCHOVER_CANDIDATE_FQDN
    fi
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
          .find do |container|
            init_body = Array(container["command"]).join("\n")
            init_body.include?("/opt/bitnami/kubectl/bin/kubectl") &&
              init_body.include?("#{expected_data_path}/tmp/bin")
          end
        abort "#{name}: missing kubectl-producing init container" unless init

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
          abort "#{name}: kubectl init does not project the expected binary"
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

  verify_rendered_completion_toolchain_for_path() {
    local chart_dir="$1"
    local expected_data_path="$2"
    shift 2
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
        mongodb = Array(component.dig("spec", "runtime", "containers"))
          .find { |container| container["name"] == "mongodb" }
        abort "#{name}: missing mongodb container" unless mongodb

        mounts = Array(mongodb["volumeMounts"])
        data_mount = mounts.find { |mount| mount["mountPath"] == expected_data_path }
        tools_mount = mounts.find { |mount| mount["mountPath"] == "/tools" }
        abort "#{name}: missing mongodb data mount" unless data_mount
        abort "#{name}: missing mongodb tools mount" unless tools_mount

        inits = Array(component.dig("spec", "runtime", "initContainers"))
        kubectl_init = inits.find do |container|
          body = Array(container["command"]).join("\n")
          body.include?("/opt/bitnami/kubectl/bin/kubectl") &&
            body.include?("#{expected_data_path}/tmp/bin")
        end
        abort "#{name}: missing kubectl-producing init container" unless kubectl_init
        kubectl_mount = Array(kubectl_init["volumeMounts"]).find do |mount|
          mount["name"] == data_mount["name"] &&
            mount["mountPath"] == expected_data_path
        end
        abort "#{name}: kubectl producer does not share mongodb data volume" unless kubectl_mount

        syncer_init = inits.find do |container|
          body = Array(container["command"]).join("\n")
          body.include?("/bin/syncerctl") && body.include?("/tools")
        end
        abort "#{name}: missing syncerctl-producing init container" unless syncer_init
        syncer_mount = Array(syncer_init["volumeMounts"]).find do |mount|
          mount["name"] == tools_mount["name"] &&
            mount["mountPath"] == "/tools"
        end
        abort "#{name}: syncer producer does not share mongodb tools volume" unless syncer_mount
      end
    '
  }

  verify_rendered_completion_toolchain() {
    local chart_dir

    chart_dir=$(cd .. && pwd)
    verify_rendered_completion_toolchain_for_path "$chart_dir" "/data/mongodb" || return
    verify_rendered_completion_toolchain_for_path \
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

  verify_resolved_action_image_matrix() {
    local chart_dir

    chart_dir=$(cd .. && pwd)
    helm template kb-addon-mongodb "$chart_dir" --dependency-update |
      ruby -ryaml -e '
      expected = {
        "8.0.17" => "docker.io/apecloud/percona-server-mongodb:8.0.17",
        "7.0.28" => "docker.io/apecloud/percona-server-mongodb:7.0.28",
        "6.0.27" => "docker.io/apecloud/percona-server-mongodb:6.0.27",
        "5.0.29" => "docker.io/apecloud/percona-server-mongodb:5.0.29-multi",
        "4.4.29" => "docker.io/apecloud/percona-server-mongodb:4.4.29-multi",
        "4.0.28" => "docker.io/apecloud/percona-server-mongodb:4.0.28"
      }
      documents = YAML.load_stream($stdin.read).compact
      components = documents.select do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("spec", "lifecycleActions", "switchover")
      end
      versions = documents.select { |document| document["kind"] == "ComponentVersion" }
      abort "expected three switchover ComponentDefinitions, got #{components.length}" unless components.length == 3
      abort "expected three ComponentVersions, got #{versions.length}" unless versions.length == 3

      rows = []
      components.each do |component|
        component_name = component.dig("metadata", "name")
        matches = versions.select do |version|
          Array(version.dig("spec", "compatibilityRules")).any? do |rule|
            Array(rule["compDefs"]).any? do |pattern|
              Regexp.new(pattern).match?(component_name)
            end
          end
        end
        unless matches.length == 1
          abort "#{component_name}: expected one compatible ComponentVersion, got #{matches.length}"
        end

        version = matches.first
        releases = Array(version.dig("spec", "releases"))
        unless releases.map { |release| release["serviceVersion"] }.sort == expected.keys.sort
          abort "#{component_name}: supported serviceVersion matrix drift"
        end

        action_names = component.dig("spec", "lifecycleActions").keys.map(&:downcase)
        releases.each do |release|
          service_version = release.fetch("serviceVersion")
          images = release.fetch("images").to_h do |name, image|
            [name.downcase, image]
          end
          resolved_actions = action_names.map { |name| images[name] }.compact
          switchover_image = images["switchover"]
          abort "#{component_name}/#{service_version}: switchover image unresolved" unless switchover_image
          unless resolved_actions.uniq == [switchover_image]
            abort "#{component_name}/#{service_version}: multiple resolved action images #{resolved_actions.uniq.inspect}"
          end
          unless switchover_image == images["mongodb"]
            abort "#{component_name}/#{service_version}: action image differs from mongodb image"
          end
          unless switchover_image == expected.fetch(service_version)
            abort "#{component_name}/#{service_version}: unexpected image #{switchover_image}"
          end
          rows << [component_name, service_version, switchover_image]
        end
      end

      abort "expected 18 resolved component/release rows, got #{rows.length}" unless rows.length == 18
      abort "expected six unique action images" unless rows.map(&:last).uniq.sort == expected.values.sort
      '
  }

  resolve_switchover_image() {
    local service_version="$1"
    local chart_dir

    chart_dir=$(cd .. && pwd)
    helm template kb-addon-mongodb "$chart_dir" --dependency-update |
      SERVICE_VERSION="$service_version" \
      ruby -ryaml -e '
      service_version = ENV.fetch("SERVICE_VERSION")
      documents = YAML.load_stream($stdin.read).compact
      component = documents.find do |document|
        document["kind"] == "ComponentDefinition" &&
          document.dig("metadata", "name").start_with?("mongodb-") &&
          document.dig("spec", "lifecycleActions", "switchover")
      end
      abort "default mongodb ComponentDefinition missing" unless component

      component_name = component.dig("metadata", "name")
      version = documents.find do |document|
        document["kind"] == "ComponentVersion" &&
          Array(document.dig("spec", "compatibilityRules")).any? do |rule|
            Array(rule["compDefs"]).any? do |pattern|
              Regexp.new(pattern).match?(component_name)
            end
          end
      end
      abort "compatible ComponentVersion missing" unless version

      release = Array(version.dig("spec", "releases")).find do |item|
        item["serviceVersion"] == service_version
      end
      abort "exact default serviceVersion release missing" unless release
      images = release.fetch("images").to_h { |name, image| [name.downcase, image] }
      image = images["switchover"]
      abort "default switchover image unresolved" unless image
      puts image
      '
  }

  run_actual_resolved_image_timeout_control() {
    local mode="$1"
    local chart_dir
    local image
    local script
    local temp_dir
    local host_timeout
    local rc

    chart_dir=$(cd .. && pwd)
    script="$chart_dir/scripts/mongodb-switchover.sh"
    image=$(resolve_switchover_image "8.0.17") || return

    # Keep the exact-parent RED bounded; the actual-image command runs once
    # the implementation contains both declared deadline surfaces.
    grep -F "timeout 10s" "$script" >/dev/null || return 101
    grep -F "timeout 3s" "$script" >/dev/null || return 101

    host_timeout=$(command -v gtimeout || command -v timeout) || return 102
    "$host_timeout" 300s docker pull --platform linux/amd64 "$image" >/dev/null ||
      return
    temp_dir=$(mktemp -d)
    mkdir -p "$temp_dir/tools"

    cat > "$temp_dir/tools/syncerctl" <<'MOCK'
#!/bin/sh
if [ "$ACTUAL_TIMEOUT_MODE" = "request" ]; then
  sleep 30
fi
printf 'ACTUAL_SYNCERCTL'
printf ' <%s>' "$@"
printf '\n'
printf 'switchover accepted\n'
MOCK
    cat > "$temp_dir/kubectl" <<'MOCK'
#!/bin/sh
if [ "$ACTUAL_TIMEOUT_MODE" = "probe" ]; then
  sleep 30
fi
MOCK
    chmod 755 \
      "$temp_dir" \
      "$temp_dir/tools" \
      "$temp_dir/tools/syncerctl" \
      "$temp_dir/kubectl"

    cat > "$temp_dir/action.env" <<ENV
ACTUAL_TIMEOUT_MODE=$mode
MONGODB_KUBECTL_BIN=/fixture/kubectl
KB_SWITCHOVER_ROLE=primary
KB_SWITCHOVER_CURRENT_NAME=mongodb-0
CLUSTER_NAMESPACE=test-ns
KB_CLUSTER_COMP_NAME=mongo-rs
ENV
    if [ "$mode" != "candidate-free" ]; then
      printf '%s\n' \
        "KB_SWITCHOVER_CANDIDATE_NAME=mongodb-1" \
        "KB_SWITCHOVER_CANDIDATE_FQDN=mongodb-1.test-ns.svc" \
        >> "$temp_dir/action.env"
    fi

    "$host_timeout" 20s docker run --rm --platform linux/amd64 \
      --volume "$chart_dir/scripts:/scripts:ro" \
      --volume "$temp_dir/tools:/tools:ro" \
      --volume "$temp_dir/kubectl:/fixture/kubectl:ro" \
      --env-file "$temp_dir/action.env" \
      --entrypoint /bin/sh \
      "$image" \
      /scripts/mongodb-switchover.sh
    rc=$?

    rm -rf "$temp_dir"
    return "$rc"
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

  It "preserves the resolved-image completion-probe timeout and classifies it"
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

  It "preserves the resolved-image syncerctl timeout status and does not probe ambiguous absence"
    When call run_switchover primary mongodb-0 mongodb-1 0 syncer-expire
    The status should equal 124
    The stderr should include "phase: syncerctl-timeout"
    The stderr should include "syncerctl-rc: 124"
    The stderr should include "next-retry-safe: no"
    The output should include "TEST:calls=TIMEOUT <10s>"
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "also classifies BusyBox-style syncerctl timeout status without false success"
    When call run_switchover primary mongodb-0 mongodb-1 0 syncer-expire-143
    The status should equal 143
    The stderr should include "phase: syncerctl-timeout"
    The stderr should include "syncerctl-rc: 143"
    The stderr should include "next-retry-safe: no"
    The output should not include "SYNCERCTL"
    The output should not include "KUBECTL"
  End

  It "also classifies BusyBox-style completion-probe timeout status without false success"
    When call run_switchover primary mongodb-0 mongodb-1 0 probe-expire-143
    The status should equal 143
    The stderr should include "phase: completion-probe-timeout"
    The stderr should include "completion-probe-rc: 143"
    The stderr should include "next-retry-safe: no"
    The output should not include "KUBECTL"
    The output should not include "SLEEP"
  End

  It "classifies a hanging request under the resolved MongoDB action image"
    When call run_actual_resolved_image_timeout_control request
    The status should equal 124
    The stderr should include "phase: syncerctl-timeout"
    The stderr should include "syncerctl-rc: 124"
    The stderr should include "next-retry-safe: no"
  End

  It "classifies a hanging completion probe under the resolved MongoDB action image"
    When call run_actual_resolved_image_timeout_control probe
    The status should equal 124
    The stderr should include "phase: completion-probe-timeout"
    The stderr should include "completion-probe-rc: 124"
    The stderr should include "next-retry-safe: no"
  End

  It "executes candidate-free switchover with candidate variables absent in the resolved MongoDB action image"
    When call run_actual_resolved_image_timeout_control candidate-free
    The status should be success
    The output should include "ACTUAL_SYNCERCTL <switchover> <--primary> <mongodb-0>"
    The output should not include "<--candidate>"
    The output should include "phase: completed"
    The output should include "completion-configmap: mongo-rs-switchover"
  End

  It "retains kubectl and syncer producers on the selected default and custom mounts"
    When call verify_rendered_completion_toolchain
    The status should be success
  End

  It "resolves one exact MongoDB action image for every supported component and service version"
    When call verify_resolved_action_image_matrix
    The status should be success
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
