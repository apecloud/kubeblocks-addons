# shellcheck shell=bash
# shellcheck disable=SC2016

Describe "NebulaGraph v1 account generation and credential consumers"
  validate_accounts() {
    helm template kb-addon-nebula .. | ruby -ryaml -e '
      definitions = YAML.load_stream($stdin.read).compact.select { |d| d["kind"] == "ComponentDefinition" }
      graphd = definitions.find { |d| d.dig("metadata", "name").start_with?("nebula-graphd-") }
      storaged = definitions.find { |d| d.dig("metadata", "name").start_with?("nebula-storaged-") }
      abort "missing graphd or storaged ComponentDefinition" unless graphd && storaged
      abort "graphd must use the v1 account API" unless graphd["apiVersion"] == "apps.kubeblocks.io/v1"
      root = graphd.fetch("spec").fetch("systemAccounts").find { |a| a["name"] == "root" }
      abort "missing initialized root account" unless root && root["initAccount"] == true
      abort "unsupported legacy password field" if root.key?("passwordGenerationPolicy")
      expected = {"length" => 16, "numDigits" => 8, "numSymbols" => 1, "symbolCharacters" => "@#%&!", "letterCase" => "MixedCases"}
      abort "missing or changed password constraints" unless root["passwordConfig"] == expected
      [graphd, storaged].each do |definition|
        name = definition.dig("metadata", "name")
        password = definition.fetch("spec").fetch("vars").find { |v| v["name"] == "NEBULA_ROOT_PASSWORD" }
        credential = password&.dig("valueFrom", "credentialVarRef")
        abort "#{name}: password must consume required root credential" unless credential && credential["name"] == "root" && credential["password"] == "Required"
        if definition == storaged
          abort "storaged must consume the graphd root account" unless credential["compDef"] == "nebula-graphd"
        end
      end
      post_provision = graphd.dig("spec", "lifecycleActions", "postProvision", "exec", "command").join(" ")
      abort "graphd must initialize the generated password" unless post_provision.include?("ALTER USER root WITH PASSWORD") && post_provision.include?("${NEBULA_ROOT_PASSWORD}")
      puts "account generation and credential consumers passed"
    '
  }

  It "renders v1 passwordConfig and binds graphd and storaged to the generated root credential"
    When call validate_accounts
    The status should be success
    The output should include "account generation and credential consumers passed"
  End
End
