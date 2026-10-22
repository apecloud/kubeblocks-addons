# shellcheck shell=sh

Describe "TiDB system account password configuration"
  chart_path() {
    printf '%s' "${TIDB_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/tidb}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_password_contract() {
    rendered=$(helm template tidb "$(chart_path)" "$@") || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      chart = YAML.safe_load(File.read(ARGV.fetch(0)))
      name = "tidb-7-#{chart.fetch("version")}"
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" && doc.dig("metadata", "name") == name }
      raise "expected one TiDB ComponentDefinition" unless definitions.length == 1
      definition = definitions.first
      raise "definition must be retained" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
      accounts = definition.fetch("spec").fetch("systemAccounts")
      raise "expected root and kbadmin" unless accounts.map { |a| a.fetch("name") }.sort == %w[kbadmin root]
      policy = {"length" => 16, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"}
      accounts.each do |account|
        account_name = account.fetch("name")
        raise "#{account_name}: legacy password field" if account.key?("passwordGenerationPolicy")
        raise "#{account_name}: missing or changed password policy" unless account["passwordConfig"] == policy
        raise "#{account_name}: wrong initialization account" unless !!account["initAccount"] == (account_name == "root")
      end
      version = docs.find { |doc| doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "tidb" }
      rules = version.fetch("spec").fetch("compatibilityRules")
      version.fetch("spec").fetch("releases").each do |release|
        patterns = rules.select { |rule| rule.fetch("releases").include?(release.fetch("name")) }
                        .flat_map { |rule| rule.fetch("compDefs") }
        raise "release #{release.fetch("name")} excludes #{name}" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
      end
      puts "root and kbadmin retain their password generation policy"
    ' "$(chart_path)/Chart.yaml"
  }

  It "renders both accounts with the current passwordConfig schema on install"
    When call check_password_contract
    The status should be success
    The output should equal "root and kbadmin retain their password generation policy"
  End

  It "renders the same password policy on upgrade without assuming live migration"
    When call check_password_contract --is-upgrade
    The status should be success
    The output should equal "root and kbadmin retain their password generation policy"
  End

  It "preserves account policies when using the Aliyun image registry"
    When call check_password_contract --set image.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
    The output should equal "root and kbadmin retain their password generation policy"
  End

  It "preserves account policies when rendering an upgrade with Aliyun images"
    When call check_password_contract --is-upgrade --set image.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
    The output should equal "root and kbadmin retain their password generation policy"
  End
End
