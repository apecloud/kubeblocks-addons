# shellcheck shell=sh
# shellcheck disable=SC2016

Describe "PgBouncer main API integration"
  main_api_contract() {
    helm dependency build .. --skip-refresh >/dev/null || return
    helm template pool .. | RUBYOPT=-W0 ruby -ryaml -e '
      docs = YAML.load_stream(ARGF.read).compact
      abort "legacy renderer remains" if docs.any? { |d| d["kind"] == "ParamConfigRenderer" }
      definition = docs.find { |d| d["kind"] == "ComponentDefinition" }
      spec = definition.fetch("spec")
      account = spec.fetch("systemAccounts").fetch(0)
      abort "legacy account API" if account.key?("passwordGenerationPolicy")
      abort "missing password policy" unless account.dig("passwordConfig", "length") == 24
      config = spec.fetch("configs").fetch(0)
      pd = docs.find { |d| d["kind"] == "ParametersDefinition" }.fetch("spec")
      abort "wrong definition binding" unless pd["componentDef"] == definition.dig("metadata", "name")
      abort "wrong template binding" unless pd["templateName"] == config["name"]
      abort "wrong format" unless pd["fileName"] == "pgbouncer.ini" && pd.dig("fileFormatConfig", "iniConfig", "sectionName") == "pgbouncer"
      abort "legacy reload" if pd.key?("reloadAction")
      action = config.fetch("reconfigure").fetch("exec")
      abort "reload misses replicas" unless action["container"] == "pgbouncer" && action["targetPodSelector"] == "All"
      abort "wrong reload command" unless action["command"] == ["/kb-scripts/pgbouncer-reload.sh"]
      pattern = spec.dig("serviceRefDeclarations", 0, "serviceRefDeclarationSpecs", 0, "serviceVersion")
      abort "invalid PostgreSQL version selector" unless Regexp.new(pattern).match?("17.11.0")
      puts "ok"
    '
  }

  It "binds parameters, account generation and every replica reload using main APIs"
    When call main_api_contract
    The status should be success
    The output should eq "ok"
  End
End
