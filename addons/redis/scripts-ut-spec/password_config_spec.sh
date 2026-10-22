# shellcheck shell=bash

Describe "Redis password configuration compatibility"
  chart_path() {
    printf '%s' "${REDIS_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/redis}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    helm template redis "$(chart_path)" "$@" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" }
      accounts = definitions.select { |doc| doc.dig("spec", "systemAccounts") }
      prefixes = %w[redis redis-cluster redis-sentinel].product(%w[5 6 7 8]).map { |parts| parts.join("-") }
      abort "expected all 12 Redis, Cluster and Sentinel account definitions" unless accounts.length == prefixes.length
      expected = [{"name" => "default", "initAccount" => true, "passwordConfig" => {
        "length" => 10, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]

      prefixes.each do |prefix|
        matches = accounts.select { |doc| doc.dig("metadata", "name").start_with?("#{prefix}-") }
        abort "expected one definition for #{prefix}" unless matches.length == 1
        definition = matches.first
        name = definition.fetch("metadata").fetch("name")
        abort "must not overwrite systemAccounts on #{name}" if name == "#{prefix}-1.2.0-alpha.0"
        abort "password policy changed or uses deprecated field on #{name}" unless definition.dig("spec", "systemAccounts") == expected
      end

      # Chart versioning also renames Twemproxy and the shared script ConfigMaps.
      definitions.each do |definition|
        name = definition.fetch("metadata").fetch("name")
        abort "definition #{name} must be retained" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
        definition.fetch("spec").fetch("scripts").each do |script|
          template = script.fetch("template")
          config = docs.find { |doc| doc["kind"] == "ConfigMap" && doc.dig("metadata", "name") == template }
          abort "missing script ConfigMap #{template} for #{name}" unless config
          abort "script ConfigMap #{template} must be retained" unless config.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
        end
      end

      %w[redis redis-cluster redis-sentinel].each do |family|
        version = docs.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == family }
        rules = version.fetch("spec").fetch("compatibilityRules")
        version.fetch("spec").fetch("releases").each do |release|
          prefix = "#{family}-#{release.fetch("serviceVersion").split(".").first}"
          name = accounts.find { |doc| doc.dig("metadata", "name").start_with?("#{prefix}-") }.fetch("metadata").fetch("name")
          patterns = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                          .flat_map { |rule| rule.fetch("compDefs") }
          ["#{prefix}-1.2.0-alpha.0", name].each do |definition_name|
            abort "#{family} release #{release.fetch("name")} excludes #{definition_name}" unless patterns.any? { |pattern| Regexp.new(pattern).match?(definition_name) }
          end
        end
      end
    '
  }

  It "installs all password policies under new retained definitions"
    When call check_rendered_accounts
    The status should be success
  End

  It "keeps old and new definitions compatible during addon upgrades"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "preserves the account contract with the Aliyun registry on install"
    When call check_rendered_accounts --set image.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
  End

  It "preserves the account contract with the Aliyun registry on upgrade"
    When call check_rendered_accounts --is-upgrade --set image.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
  End
End
