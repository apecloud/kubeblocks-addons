# shellcheck shell=bash

Describe "OceanBase CE system account password configuration"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/oceanbase-ce"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_rendered_accounts() {
    local rendered
    rendered=$(helm template password-contract "$(chart_path)" "$@") || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      definitions = YAML.load_stream(STDIN.read).compact.select { |doc| doc["kind"] == "ComponentDefinition" }
      abort "expected one OceanBase CE ComponentDefinition" unless definitions.length == 1
      expected = [{"name" => "root", "initAccount" => true, "passwordConfig" => {
        "length" => 10, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]
      definitions.each do |definition|
        accounts = definition.fetch("spec").fetch("systemAccounts")
        abort "root passwordConfig missing, legacy field present, or password rules changed" unless accounts == expected
        credential = definition.fetch("spec").fetch("vars").find { |var| var["name"] == "OB_ROOT_PASSWD" }
        expected_ref = {"name" => "root", "optional" => false, "password" => "Required"}
        abort "root credential reference changed" unless credential.dig("valueFrom", "credentialVarRef") == expected_ref
      end
    '
  }

  check_versioned_definition() {
    local rendered
    rendered=$(helm template password-contract "$(chart_path)" --is-upgrade) || return
    printf '%s\n' "$rendered" | ruby -ryaml -rrubygems -e '
      chart = YAML.load_file(ARGV.fetch(0))
      abort "chart must advance beyond the legacy account definition" unless Gem::Version.new(chart.fetch("version")) > Gem::Version.new("1.2.0-alpha.0")
      abort "KubeBlocks compatibility changed" unless chart.fetch("annotations").fetch("addon.kubeblocks.io/kubeblocks-version") == ">=1.2.0"
      docs = YAML.load_stream(STDIN.read).compact
      definition = docs.find { |doc| doc["kind"] == "ComponentDefinition" }
      name = definition.fetch("metadata").fetch("name")
      abort "definition must use the new chart version" unless name == "oceanbase-ce-#{chart.fetch("version")}"
      abort "default resource retention changed" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
      versions = docs.find { |doc| doc["kind"] == "ComponentVersion" }.fetch("spec")
      versions.fetch("releases").each do |release|
        patterns = versions.fetch("compatibilityRules")
                           .select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                           .flat_map { |rule| rule.fetch("compDefs") }
        abort "database version no longer matches new definition" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
      end
      cluster = docs.find { |doc| doc["kind"] == "ClusterDefinition" }
      components = cluster.fetch("spec").fetch("topologies").flat_map { |topology| topology.fetch("components") }
      abort "cluster topology no longer matches new definition" unless components.all? { |component| Regexp.new(component.fetch("compDef")).match?(name) }
    ' "$(chart_path)/Chart.yaml"
  }

  It "renders explicit root password generation with the original policy"
    When call check_rendered_accounts
    The status should be success
  End

  It "preserves the same password rules in upgrade rendering"
    When call check_rendered_accounts --is-upgrade
    The status should be success
  End

  It "preserves the account with name overrides and resource retention disabled"
    When call check_rendered_accounts --set nameOverride=custom-ob --set fullnameOverride=custom-ob-full --set extra.keepResource=false
    The status should be success
  End

  It "uses a new immutable definition identity matched by the topology and every database version"
    When call check_versioned_definition
    The status should be success
  End
End
