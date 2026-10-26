# shellcheck shell=sh

Describe "Kafka system account password configuration"
  chart_path() {
    printf '%s' "${KAFKA_CHART_PATH:-${SHELLSPEC_CWD:?}/addons/kafka}"
  }

  build_dependencies() {
    helm dependency build "$(chart_path)" >/dev/null
  }
  BeforeAll 'build_dependencies'

  check_password_contract() {
    rendered=$(helm template kafka "$(chart_path)" "$@") || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      docs = YAML.load_stream(STDIN.read).compact
      chart = YAML.safe_load(File.read(ARGV.fetch(0)))
      expected = {
        "kafka-combine-#{chart.fetch("version")}" => ["kafka-combine", "3."],
        "kafka-broker-#{chart.fetch("version")}" => ["kafka-broker", "3."],
        "kafka27-broker-#{chart.fetch("version")}" => ["kafka-broker", "2."]
      }
      definitions = docs.select { |doc| doc["kind"] == "ComponentDefinition" && doc.dig("spec", "systemAccounts") }
      raise "unexpected account-bearing definitions" unless definitions.map { |d| d.dig("metadata", "name") }.sort == expected.keys.sort
      policy = {"length" => 16, "numDigits" => 8, "letterCase" => "MixedCases"}
      definitions.each do |definition|
        name = definition.fetch("metadata").fetch("name")
        raise "#{name}: definition must be retained" unless definition.dig("metadata", "annotations", "helm.sh/resource-policy") == "keep"
        accounts = definition.fetch("spec").fetch("systemAccounts")
        raise "#{name}: expected client and admin" unless accounts.map { |a| a.fetch("name") }.sort == %w[admin client]
        accounts.each do |account|
          label = "#{name}/#{account.fetch("name")}"
          raise "#{label}: legacy password field" if account.key?("passwordGenerationPolicy")
          raise "#{label}: missing or changed password policy" unless account["passwordConfig"] == policy
          raise "#{label}: initialization role changed" unless account["initAccount"] == true
        end
        version_name, service_prefix = expected.fetch(name)
        version = docs.find { |d| d["kind"] == "ComponentVersion" && d.dig("metadata", "name") == version_name }
        releases = version.fetch("spec").fetch("releases").select { |r| r.fetch("serviceVersion").start_with?(service_prefix) }
        raise "#{name}: no supported releases" if releases.empty?
        rules = version.fetch("spec").fetch("compatibilityRules")
        releases.each do |release|
          patterns = rules.select { |r| r.fetch("releases").include?(release.fetch("name")) }.flat_map { |r| r.fetch("compDefs") }
          raise "#{name}: release #{release.fetch("name")} excludes definition" unless patterns.any? { |pattern| Regexp.new(pattern).match?(name) }
        end
      end
      puts "six Kafka accounts retain their password policy and version compatibility"
    ' "$(chart_path)/Chart.yaml"
  }

  It "renders all six accounts with passwordConfig on install"
    When call check_password_contract
    The status should be success
    The output should equal "six Kafka accounts retain their password policy and version compatibility"
  End

  It "preserves the policy in upgrade rendering without assuming live migration"
    When call check_password_contract --is-upgrade
    The status should be success
    The output should equal "six Kafka accounts retain their password policy and version compatibility"
  End

  It "preserves the policy with the Aliyun image registry"
    When call check_password_contract --set images.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
    The output should equal "six Kafka accounts retain their password policy and version compatibility"
  End

  It "preserves the policy for upgrades with Aliyun images"
    When call check_password_contract --is-upgrade --set images.registry=apecloud-registry.cn-zhangjiakou.cr.aliyuncs.com
    The status should be success
    The output should equal "six Kafka accounts retain their password policy and version compatibility"
  End
End
