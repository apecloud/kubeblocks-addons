# shellcheck shell=bash
# shellcheck disable=SC2016

Describe "MySQL chart completeness contracts"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/mysql"
  }

  prepare_chart() {
    helm dependency build "$(chart_path)" >/dev/null
  }

  render_chart() {
    helm template mysql "$(chart_path)" "$@"
  }

  validate_parameters_definition_ownership() {
    local render_dir status
    render_dir=$(mktemp -d)

    render_chart >"$render_dir/default.yaml" &&
      render_chart --set resourceNamePrefix=static-resource >"$render_dir/resource-prefix.yaml" &&
      render_chart --set cmpdNamePrefix=static-cmpd >"$render_dir/cmpd-prefix.yaml" &&
      render_chart --set resourceNamePrefix=static-resource \
        --set cmpdNamePrefix=static-cmpd >"$render_dir/both-prefixes.yaml" &&
      ruby -ryaml -e '
        ARGV.each do |path|
          documents = YAML.load_stream(File.read(path)).compact
          definitions = documents.select { |doc| doc["kind"] == "ComponentDefinition" }
          parameter_definitions = documents.select { |doc| doc["kind"] == "ParametersDefinition" }

          owners = definitions.select do |definition|
            Array(definition.dig("spec", "configs")).any? do |config|
              config["name"] == "mysql-replication-config" && config["externalManaged"] == true
            end
          end
          abort "#{path}: expected seven externally managed MySQL config owners" unless owners.length == 7
          abort "#{path}: expected two ParametersDefinitions" unless parameter_definitions.length == 2

          matchers = parameter_definitions.map do |definition|
            [definition.dig("metadata", "name"), Regexp.new(definition.dig("spec", "componentDef"))]
          end
          owners.each do |owner|
            name = owner.dig("metadata", "name")
            matching = matchers.select { |_pd_name, matcher| matcher.match?(name) }
            unless matching.length == 1
              abort "#{path}: #{name} is covered #{matching.length} times by #{matching.map(&:first).join(",")}"
            end

            config = Array(owner.dig("spec", "configs")).find do |candidate|
              candidate["name"] == "mysql-replication-config"
            end
            command = config.dig("reconfigure", "exec", "command")
            abort "#{path}: #{name} lacks a deterministic reconfigure argv contract" unless
              command.is_a?(Array) &&
              command.last == "--" &&
              command.join("\n").include?("/scripts/update-parameter.sh \"$@\"")
          end

          mysql84 = owners.select { |owner| owner.dig("spec", "serviceVersion").to_s.start_with?("8.4.") }
          abort "#{path}: expected two MySQL 8.4 config owners" unless mysql84.length == 2
          mysql84.each do |owner|
            name = owner.dig("metadata", "name")
            matching = matchers.select { |_pd_name, matcher| matcher.match?(name) }
            abort "#{path}: MySQL 8.4 owner #{name} is not covered exactly once" unless matching.length == 1
          end
        end

        puts "MySQL ParametersDefinition ownership contract passed for #{ARGV.length} renders"
      ' "$render_dir/default.yaml" "$render_dir/resource-prefix.yaml" \
        "$render_dir/cmpd-prefix.yaml" "$render_dir/both-prefixes.yaml"
    status=$?

    rm -rf "$render_dir"
    return "$status"
  }

  validate_general_log_defaults() {
    grep -Eq '^general_log=OFF$' "$(chart_path)/config/mysql5.7-config.tpl" &&
      grep -Eq '^general_log=OFF$' "$(chart_path)/config/mysql8.0-config.tpl"
  }

  validate_pitr_cleanup_contract() {
    local rendered
    rendered=$(render_chart --show-only templates/actionset-pitr.yaml) || return
    printf '%s' "$rendered" | ruby -ryaml -e '
      action_set = YAML.safe_load(STDIN.read, permitted_classes: [Time], aliases: true)
      env = action_set.dig("spec", "env").to_h { |entry| [entry.fetch("name"), entry.fetch("value")] }
      abort "missing PITR purge threshold env" unless env["PURGE_BINLOG_DISK_THRESHOLD"] == "80"
      abort "TIME_FORMAT must remain a string" unless env["TIME_FORMAT"].is_a?(String)
    ' &&
      grep -Fq 'PURGE_BINLOG_DISK_THRESHOLD:-80' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'information_schema.PROCESSLIST' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'grep -F "${LOG_PREFIX}."' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'if ! synced_binlogs=$(get_synced_binlogs)' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq "PURGE BINARY LOGS TO '\$first_kept'" \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'mysql-pitr-binlog-purge.sh' \
        "$(chart_path)/templates/actionset-pitr.yaml"
  }

  validate_actionset_env_contracts() {
    render_chart | ruby -ryaml -e '
      action_sets = YAML.load_stream(STDIN.read).compact.select do |document|
        document["kind"] == "ActionSet"
      end
      abort "expected rendered ActionSets" if action_sets.empty?

      action_sets.each do |action_set|
        seen = {}
        Array(action_set.dig("spec", "env")).each do |entry|
          name = entry["name"]
          abort "#{action_set.dig("metadata", "name")}: empty env name" if name.to_s.empty?
          abort "#{action_set.dig("metadata", "name")}: duplicate env #{name}" if seen[name]
          seen[name] = true

          has_value = entry.key?("value")
          has_value_from = entry.key?("valueFrom")
          abort "#{action_set.dig("metadata", "name")}: env #{name} has an invalid source" if
            has_value == has_value_from
          abort "#{action_set.dig("metadata", "name")}: env #{name} value is not a string" if
            has_value && !entry["value"].is_a?(String)
        end
      end

      puts "ActionSet env contracts passed for #{action_sets.length} resources"
    '
  }

  validate_reconfigure_assets() {
    render_chart --show-only templates/scripts.yaml | ruby -ryaml -e '
      scripts = YAML.load_stream(STDIN.read).compact.find do |document|
        document["kind"] == "ConfigMap" && document.dig("metadata", "name") == "mysql-scripts"
      end
      abort "mysql-scripts ConfigMap is missing" unless scripts

      update_script = scripts.dig("data", "update-parameter.sh")
      abort "update-parameter.sh is missing" if update_script.to_s.empty?
      {
        "mysql5.7-dynamic-parameters.txt" => %w[general_log max_connections],
        "mysql8-dynamic-parameters.txt" => %w[general_log max_connections]
      }.each do |file, required|
        parameters = scripts.dig("data", file).to_s.lines.map(&:strip).reject(&:empty?)
        abort "#{file} is empty" if parameters.empty?
        abort "#{file} contains duplicate parameters" unless parameters.uniq.length == parameters.length
        missing = required - parameters
        abort "#{file} is missing #{missing.join(",")}" unless missing.empty?
        abort "update script does not consume #{file}" unless update_script.include?("/scripts/#{file}")
      end
    '
  }

  validate_reconfigure_wrapper_argv() {
    local command mock zero_argv two_argv status
    command=$(render_chart --show-only templates/cmpd-mysql80.yaml | ruby -ryaml -e '
      definition = YAML.safe_load(STDIN.read, aliases: true)
      config = Array(definition.dig("spec", "configs")).find do |candidate|
        candidate["name"] == "mysql-replication-config"
      end
      puts config.dig("reconfigure", "exec", "command", 2)
    ') || return

    mock=$(mktemp)
    cat >"$mock" <<'MOCK'
#!/bin/bash
printf '%s\n' "$#"
MOCK
    chmod +x "$mock"
    command="${command//\/scripts\/update-parameter.sh/$mock}"

    zero_argv=$(bash -c "$command" --)
    status=$?
    if [ "$status" -eq 0 ]; then
      two_argv=$(bash -c "$command" -- max_connections 500)
      status=$?
    fi
    rm -f "$mock"

    [ "$status" -eq 0 ] &&
      [ "$zero_argv" = "0" ] &&
      [ "$two_argv" = "2" ]
  }

  validate_orchestrator_lifecycle_contract() {
    render_chart --show-only templates/cmpd-mysql80-orc.yaml |
      ruby -ryaml -e '
        definition = YAML.safe_load(STDIN.read, aliases: true)
        actions = definition.dig("spec", "lifecycleActions")
        role_probe = actions.fetch("roleProbe")
        switchover = actions.fetch("switchover")

        abort "roleProbe failureThreshold is not rendered" unless role_probe["failureThreshold"] == 3
        abort "roleProbe periodSeconds is too aggressive" unless role_probe["periodSeconds"] >= 3
        abort "roleProbe timeoutSeconds is too aggressive" unless role_probe["timeoutSeconds"] >= 2

        outer = switchover["timeoutSeconds"]
        abort "switchover timeout must be explicit and within the kbagent cap" unless outer.is_a?(Integer) && outer.between?(1, 60)
        command = switchover.dig("exec", "command").join("\n")
        abort "switchover command lacks an inner timeout" unless command.include?("SWITCHOVER_COMMAND_TIMEOUT_SECONDS")
      '
  }

  validate_orchestrator_override_contract() {
    render_chart --show-only templates/cmpd-mysql80-orc.yaml \
      --set roleProbe.failureThreshold=4 \
      --set roleProbe.periodSeconds=7 \
      --set roleProbe.timeoutSeconds=4 \
      --set orchestrator.switchover.timeoutSeconds=45 \
      --set orchestrator.switchover.commandTimeoutSeconds=30 |
      ruby -ryaml -e '
        definition = YAML.safe_load(STDIN.read, aliases: true)
        actions = definition.dig("spec", "lifecycleActions")
        role_probe = actions.fetch("roleProbe")
        switchover = actions.fetch("switchover")
        env = switchover.dig("exec", "env").to_h { |entry| [entry.fetch("name"), entry.fetch("value")] }

        abort "failureThreshold override was ignored" unless role_probe["failureThreshold"] == 4
        abort "periodSeconds override was ignored" unless role_probe["periodSeconds"] == 7
        abort "timeoutSeconds override was ignored" unless role_probe["timeoutSeconds"] == 4
        abort "outer switchover override was ignored" unless switchover["timeoutSeconds"] == 45
        abort "inner switchover override was ignored" unless env["SWITCHOVER_COMMAND_TIMEOUT_SECONDS"] == "30"
      '
  }

  reject_unbounded_orchestrator_timeout() {
    render_chart --show-only templates/cmpd-mysql80-orc.yaml \
      --set orchestrator.switchover.timeoutSeconds=61 >/dev/null
  }

  BeforeAll "prepare_chart"

  It "covers every externally managed config owner exactly once, including MySQL 8.4"
    When call validate_parameters_definition_ownership
    The status should be success
    The output should include "passed for 4 renders"
  End

  It "keeps general logging disabled by default for MySQL 5.7 and 8.x"
    When call validate_general_log_defaults
    The status should be success
  End

  It "renders and consumes the complete fail-closed PITR cleanup env contract"
    When call validate_pitr_cleanup_contract
    The status should be success
  End

  It "keeps every rendered ActionSet env source unique and string-safe"
    When call validate_actionset_env_contracts
    The status should be success
    The output should include "ActionSet env contracts passed"
  End

  It "renders version-specific dynamic allowlists consumed by the argv fallback"
    When call validate_reconfigure_assets
    The status should be success
  End

  It "executes the rendered reconfigure wrapper with either zero or two arguments"
    When call validate_reconfigure_wrapper_argv
    The status should be success
  End

  It "renders bounded Orchestrator role-probe and switchover action budgets"
    When call validate_orchestrator_lifecycle_contract
    The status should be success
  End

  It "honors chart overrides for both Orchestrator probe and action budgets"
    When call validate_orchestrator_override_contract
    The status should be success
  End

  It "rejects an Orchestrator action budget above the kbagent clamp"
    When call reject_unbounded_orchestrator_timeout
    The status should be failure
    The stderr should include "must be between 1 and 60"
  End
End
