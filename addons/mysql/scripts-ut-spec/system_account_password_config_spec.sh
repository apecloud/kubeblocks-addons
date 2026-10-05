# shellcheck shell=sh

Describe "MySQL system account passwordConfig identity contract"
  chart_path() {
    printf '%s' "${SHELLSPEC_CWD:?}/addons/mysql"
  }

  expected_chart_version() {
    printf '%s' "1.2.0-alpha.1"
  }

  cmpd_templates() {
    printf '%s\n' \
      "cmpd-mysql57.yaml" \
      "cmpd-mysql80.yaml" \
      "cmpd-mysql84.yaml" \
      "cmpd-mysql80-mgr.yaml" \
      "cmpd-mysql84-mgr.yaml" \
      "cmpd-mysql57-orc.yaml" \
      "cmpd-mysql80-orc.yaml" \
      "cmpd-proxysql.yaml"
  }

  expected_cmpd_names() {
    printf '%s\n' \
      "mysql-5.7-1.2.0-alpha.1" \
      "mysql-8.0-1.2.0-alpha.1" \
      "mysql-8.4-1.2.0-alpha.1" \
      "mysql-mgr-8.0-1.2.0-alpha.1" \
      "mysql-mgr-8.4-1.2.0-alpha.1" \
      "mysql-orc-5.7-1.2.0-alpha.1" \
      "mysql-orc-8.0-1.2.0-alpha.1" \
      "proxysql-mysql-1.2.0-alpha.1"
  }

  render_template() {
    helm template mysql "$(chart_path)" --show-only "templates/$1"
  }

  inspect_cmpd() {
    render_template "$1" | ruby -ryaml -e '
      document = YAML.safe_load(STDIN.read, aliases: true)
      raise "expected ComponentDefinition" unless document.fetch("kind") == "ComponentDefinition"
      name = document.fetch("metadata").fetch("name")
      accounts = document.fetch("spec").fetch("systemAccounts")
      raise "#{name}: expected systemAccounts" if accounts.nil? || accounts.empty?
      accounts.each do |account|
        account_name = account.fetch("name")
        raise "#{name}/#{account_name}: passwordGenerationPolicy must be absent" if account.key?("passwordGenerationPolicy")
        config = account["passwordConfig"]
        raise "#{name}/#{account_name}: passwordConfig missing" if config.nil? || config.empty?
        raise "#{name}/#{account_name}: passwordConfig.length missing" unless config["length"].to_i > 0
      end
      puts name
    '
  }

  assert_chart_version() {
    version=$(ruby -ryaml -e 'puts YAML.safe_load(File.read(ARGV[0])).fetch("version")' "$(chart_path)/Chart.yaml") || return
    printf 'chart_version=%s\n' "$version"
    [ "$version" = "$(expected_chart_version)" ]
  }

  assert_cmpd_identities_and_password_config() {
    names=$(cmpd_templates | while IFS= read -r template; do
      inspect_cmpd "$template" || exit 1
    done | sort) || return
    expected=$(expected_cmpd_names | sort)
    printf 'cmpd_names=%s\n' "$(printf '%s' "$names" | tr '\n' ',')"
    [ "$names" = "$expected" ]
  }

  It "bumps the MySQL chart identity to 1.2.0-alpha.1"
    When call assert_chart_version
    The status should be success
    The output should include "chart_version=1.2.0-alpha.1"
  End

  It "renders eight new CMPD identities with passwordConfig and no passwordGenerationPolicy"
    When call assert_cmpd_identities_and_password_config
    The status should be success
    The output should include "mysql-8.0-1.2.0-alpha.1"
    The output should include "proxysql-mysql-1.2.0-alpha.1"
  End
End
