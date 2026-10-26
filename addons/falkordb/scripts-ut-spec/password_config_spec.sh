# shellcheck shell=bash

Describe "FalkorDB system account password configuration"
  chart_path() {
    printf '%s' "${FALKORDB_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/falkordb}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    local rendered
    rendered=$(helm template falkordb "$(chart_path)" "$@") || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" }
      expected_names = %w[falkordb-4-1.2.0-alpha.0 falkordb-sent-4-1.2.0-alpha.0 falkordb-cluster-4-1.2.0-alpha.0]
      names = definitions.map { |doc| doc.fetch("metadata").fetch("name") }
      abort "ComponentDefinition identities changed" unless names.sort == expected_names.sort

      definitions.each do |definition|
        name = definition.fetch("metadata").fetch("name")
        policy = {"length" => 10, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"}
        policy["seed"] = "5wM4uhmKV1Ohy087" if name.start_with?("falkordb-cluster-")
        expected = [{"name" => "default", "initAccount" => true, "passwordConfig" => policy}]
        abort "#{name}: default account policy changed or uses deprecated field" unless definition.dig("spec", "systemAccounts") == expected
      end

      shardings = docs.select { |doc| doc["kind"] == "ShardingDefinition" }
      abort "expected one ShardingDefinition" unless shardings.length == 1
      abort "shared default account changed" unless shardings.first.dig("spec", "systemAccounts") == [{"name" => "default", "shared" => true}]

      versions = docs.select { |doc| doc["kind"] == "ComponentVersion" }
      abort "expected three ComponentVersions" unless versions.length == 3
      versions.each do |version|
        prefix = version.fetch("metadata").fetch("name")
        name = "#{prefix}-4-1.2.0-alpha.0"
        abort "#{prefix}: missing ComponentDefinition" unless names.include?(name)
        rules = version.fetch("spec").fetch("compatibilityRules")
        version.fetch("spec").fetch("releases").each do |release|
          patterns = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                          .flat_map { |rule| rule.fetch("compDefs") }
          abort "#{prefix}/#{release.fetch("name")}: incompatible definition" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
        end
      end
    '
  }

  check_chart_contract() {
    ruby -ryaml -e '
      chart = YAML.load_file(ARGV.fetch(0))
      abort "chart version changed" unless chart.fetch("version") == "1.2.0-alpha.0"
      supported = chart.fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version")
      abort "KubeBlocks compatibility changed" unless supported == ">=1.2.0"
    ' "$(chart_path)/Chart.yaml"
  }

  It "renders all three password policies and preserves shared accounts and release compatibility"
    When call check_rendered_accounts
    The status should be success
  End

  It "preserves the same policies and identities in upgrade rendering"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "preserves the policies when metrics are disabled"
    When call check_rendered_accounts --set enableMetrics=false
    The status should be success
  End

  It "preserves the chart identity and KubeBlocks 1.2 compatibility requirement"
    When call check_chart_contract
    The status should be success
  End
End
