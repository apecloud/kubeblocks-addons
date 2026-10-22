# shellcheck shell=sh

Describe "Milvus proxy passwordConfig identity contract"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/milvus"
  }

  render_proxy() {
    helm template milvus "$(chart_path)" --show-only templates/cmpd-proxy.yaml
  }

  assert_proxy_identity_and_account_schema() {
    render_proxy | ruby -ryaml -e '
      document = YAML.safe_load(STDIN.read, aliases: true)
      name = document.fetch("metadata").fetch("name")
      abort "proxy ComponentDefinition identity still reuses alpha.1" if name == "milvus-proxy-1.2.0-alpha.1"
      abort "unexpected proxy ComponentDefinition identity: #{name}" unless name == "milvus-proxy-1.2.0-alpha.2"

      root = document.fetch("spec").fetch("systemAccounts").find { |account| account.fetch("name") == "root" }
      abort "root account is missing" unless root
      abort "passwordGenerationPolicy must be absent" if root.key?("passwordGenerationPolicy")
      config = root.fetch("passwordConfig")
      abort "passwordConfig must be non-empty" unless config.is_a?(Hash) && config["length"].to_i > 0
      abort "passwordConfig length changed" unless config["length"] == 16
      abort "passwordConfig digit count changed" unless config["numDigits"] == 4
      abort "passwordConfig symbol count changed" unless config["numSymbols"] == 0
      abort "passwordConfig letter case changed" unless config["letterCase"] == "MixedCases"

      puts "proxy=#{name}"
      puts "passwordConfig=#{config.values_at("length", "numDigits", "numSymbols", "letterCase").join(",")}"
    '
  }

  It "publishes passwordConfig under a new immutable proxy identity"
    When call assert_proxy_identity_and_account_schema
    The status should be success
    The output should eq "proxy=milvus-proxy-1.2.0-alpha.2
passwordConfig=16,4,0,MixedCases"
  End
End
