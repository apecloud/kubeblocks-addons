# shellcheck shell=bash

Describe "RabbitMQ v1 root generation and credential consumers"
  validate_root_account() {
    helm template kb-addon-rabbitmq .. | ruby -ryaml -e '
      definitions = YAML.load_stream($stdin.read).compact.select { |d| d["kind"] == "ComponentDefinition" }
      abort "expected one RabbitMQ ComponentDefinition" unless definitions.size == 1
      definition = definitions.first
      root = definition.fetch("spec").fetch("systemAccounts").find { |a| a["name"] == "root" }
      abort "missing initialized root" unless root && root["initAccount"] == true
      abort "unsupported legacy password field" if root.key?("passwordGenerationPolicy")
      expected = {"length" => 16, "numDigits" => 8, "numSymbols" => 0, "letterCase" => "MixedCases"}
      abort "missing or changed password constraints" unless root["passwordConfig"] == expected
      vars = definition.fetch("spec").fetch("vars")
      {"RABBITMQ_DEFAULT_USER" => "username", "RABBITMQ_DEFAULT_PASS" => "password"}.each do |name, field|
        credential = vars.find { |v| v["name"] == name }.dig("valueFrom", "credentialVarRef")
        abort "#{name}: root credential consumer changed" unless credential["name"] == "root" && credential[field] == "Required" && credential["optional"] == false
      end
      puts "v1 root password generation and consumers passed"
    '
  }

  It "renders passwordConfig without changing password constraints or required consumers"
    When call validate_root_account
    The status should be success
    The output should include "v1 root password generation and consumers passed"
  End
End
