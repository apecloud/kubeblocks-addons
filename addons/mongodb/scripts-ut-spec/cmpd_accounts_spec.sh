# shellcheck shell=bash

Describe "MongoDB v1 account generation and credential consumers"
  validate_accounts() {
    helm template kb-addon-mongodb .. | ruby -ryaml -e '
      definitions = YAML.load_stream($stdin.read).compact.select { |d| d["kind"] == "ComponentDefinition" }
      accounts = definitions.select { |d| d.dig("spec", "systemAccounts")&.any? }
      abort "expected replica-set and config-server account producers" unless accounts.size == 2
      expected = {"length" => 16, "numDigits" => 8, "numSymbols" => 0, "letterCase" => "MixedCases"}
      accounts.each do |definition|
        name = definition.dig("metadata", "name")
        root = definition.fetch("spec").fetch("systemAccounts").find { |a| a["name"] == "root" }
        abort "#{name}: missing initialized root" unless root && root["initAccount"] == true
        abort "#{name}: unsupported legacy password field" if root.key?("passwordGenerationPolicy")
        abort "#{name}: missing or changed password constraints" unless root["passwordConfig"] == expected
        vars = definition.fetch("spec").fetch("vars")
        credential = vars.find { |v| v["name"] == "MONGODB_PASSWORD" }.dig("valueFrom", "credentialVarRef")
        abort "#{name}: password must consume required root credential" unless credential["name"] == "root" && credential["password"] == "Required" && credential["optional"] == false
        container = definition.dig("spec", "runtime", "containers").find { |c| c["name"] == "mongodb" }
        password = container.fetch("env").find { |v| v["name"] == "MONGODB_ROOT_PASSWORD" }
        abort "#{name}: entry password alias changed" unless password["value"] == "$(MONGODB_PASSWORD)"
      end
      puts "account generation and entry consumers passed"
    '
  }

  It "renders v1 passwordConfig and preserves required root password consumers"
    When call validate_accounts
    The status should be success
    The output should include "account generation and entry consumers passed"
  End
End
