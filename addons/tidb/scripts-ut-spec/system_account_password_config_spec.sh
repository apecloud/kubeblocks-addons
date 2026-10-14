# shellcheck shell=sh

Describe "TiDB system account password configuration"
  render_tidb() {
    helm template tidb "${SHELLSPEC_CWD:?}/addons/tidb" \
      --show-only templates/cmpd-tidb.yaml
  }

  check_password_contract() {
    rendered=$(render_tidb) || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      doc = YAML.safe_load(STDIN.read, aliases: true)
      accounts = doc.fetch("spec").fetch("systemAccounts")
      raise "expected root and kbadmin" unless accounts.map { |a| a.fetch("name") }.sort == %w[kbadmin root]
      policy = {"length" => 16, "numDigits" => 5, "numSymbols" => 0, "letterCase" => "MixedCases"}
      accounts.each do |account|
        name = account.fetch("name")
        raise "#{name}: legacy password field" if account.key?("passwordGenerationPolicy")
        raise "#{name}: missing or changed password policy" unless account["passwordConfig"] == policy
        raise "#{name}: wrong initialization account" unless !!account["initAccount"] == (name == "root")
      end
      puts "root and kbadmin retain their password generation policy"
    '
  }

  check_component_identity() {
    rendered=$(render_tidb) || return
    printf '%s\n' "$rendered" | ruby -ryaml -e '
      doc = YAML.safe_load(STDIN.read, aliases: true)
      chart = YAML.safe_load(File.read(ARGV.fetch(0)))
      version = chart.fetch("version")
      raise "immutable accounts require a new ComponentDefinition" if version == "1.2.0-alpha.0"
      raise "unexpected ComponentDefinition identity" unless doc.fetch("metadata").fetch("name") == "tidb-7-#{version}"
      puts "password migration uses a new ComponentDefinition identity"
    ' "${SHELLSPEC_CWD:?}/addons/tidb/Chart.yaml"
  }

  It "renders both accounts with the current passwordConfig schema"
    When call check_password_contract
    The status should be success
    The output should equal "root and kbadmin retain their password generation policy"
  End

  It "does not overwrite the immutable system accounts of the old ComponentDefinition"
    When call check_component_identity
    The status should be success
    The output should equal "password migration uses a new ComponentDefinition identity"
  End
End
