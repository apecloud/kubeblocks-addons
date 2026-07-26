# shellcheck shell=bash

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
    ' &&
      grep -Fq 'PURGE_BINLOG_DISK_THRESHOLD:-80' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'information_schema.PROCESSLIST' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'grep -F "${LOG_PREFIX}."' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh" &&
      grep -Fq 'if ! synced_binlogs=$(get_synced_binlogs)' \
        "$(chart_path)/dataprotection/mysql-pitr-backup.sh"
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

  It "renders bounded Orchestrator role-probe and switchover action budgets"
    When call validate_orchestrator_lifecycle_contract
    The status should be success
  End
End
