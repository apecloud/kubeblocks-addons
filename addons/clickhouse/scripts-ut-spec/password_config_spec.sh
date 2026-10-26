# shellcheck shell=bash

Describe "ClickHouse system account password configuration"
  chart_path() {
    printf '%s' "${CLICKHOUSE_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/clickhouse}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_password_contract() {
    local rendered
    rendered=$(helm template clickhouse "$(chart_path)" "$@") || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      chart = YAML.load_file(ARGV.fetch(0))
      raise "supported KubeBlocks range changed" unless chart.dig("annotations", "addon.kubeblocks.io/kubeblocks-version") == ">=1.2.0"
      names = %w[clickhouse-1.2.0-alpha.1 clickhouse-22-1.2.0-alpha.1]
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" && names.include?(doc.dig("metadata", "name")) }
      raise "expected both versioned server definitions" unless definitions.map { |doc| doc.dig("metadata", "name") }.sort == names.sort
      expected = [{"name" => "admin", "initAccount" => true, "passwordConfig" => {
        "length" => 10, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"
      }}]
      definitions.each do |definition|
        name = definition.dig("metadata", "name")
        raise "#{name}: admin password policy missing, changed, or using legacy field" unless definition.dig("spec", "systemAccounts") == expected
        password = definition.fetch("spec").fetch("vars").find { |var| var["name"] == "CLICKHOUSE_ADMIN_PASSWORD" }
        raise "#{name}: credential reference changed" unless password.dig("valueFrom", "credentialVarRef") == {"name" => "admin", "optional" => false, "password" => "Required"}
      end
      version = docs.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "clickhouse" }
      rules = version.fetch("spec").fetch("compatibilityRules")
      version.fetch("spec").fetch("releases").each do |release|
        release_name = release.fetch("name")
        patterns = rules.select { |rule| rule.fetch("releases").include?(release_name) }.flat_map { |rule| rule.fetch("compDefs") }
        required = release_name.split(".").first.to_i < 23 ? names : names.first(1)
        required.each do |name|
          raise "release #{release_name} excludes #{name}" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
        end
      end
    ' "$(chart_path)/Chart.yaml"
  }

  It "renders both server accounts with passwordConfig on install"
    When call check_password_contract
    The status should be success
  End

  It "preserves admin policy and definition identities in upgrade rendering"
    When call check_password_contract --is-upgrade
    The status should be success
  End

  It "preserves both accounts with the Aliyun image registry"
    When call check_password_contract --set image.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
  End

  It "preserves both accounts in upgrade rendering with Aliyun images"
    When call check_password_contract --is-upgrade --set image.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
  End
End
