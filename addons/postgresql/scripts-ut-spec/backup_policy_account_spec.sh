# shellcheck shell=bash

Describe "PostgreSQL backup policy accounts"
  rendered_accounts() {
    helm template kb-addon-postgresql .. --namespace kb-system --dependency-update |
      ruby -ryaml -e '
        documents = YAML.load_stream(ARGF.read).compact
        policy = documents.find { |item| item["kind"] == "BackupPolicyTemplate" }.fetch("spec")
        default_account = policy.fetch("target").fetch("account")
        methods = policy.fetch("backupMethods").reject { |method| method["snapshotVolumes"] }
        methods.each do |method|
          account = method.dig("target", "account") || default_account
          puts "#{method.fetch("name")}=#{account}"
        end
        definitions = documents.select { |item| item["kind"] == "ComponentDefinition" && item.dig("spec", "serviceKind") == "PostgreSQL" }
        abort "missing backup account" unless !definitions.empty? && definitions.all? do |definition|
          definition.fetch("spec").fetch("systemAccounts").any? { |account| account["name"] == default_account }
        end
      '
  }

  It "uses an existing kbadmin system account for every SQL backup method"
    When call rendered_accounts
    The status should eq 0
    The output should include "pg-basebackup=kbadmin"
    The output should include "pgdump=kbadmin"
    The output should include "pgdumpall=kbadmin"
    The output should include "wal-g=kbadmin"
    The output should include "wal-g-incremental=kbadmin"
    The output should include "archive-wal=kbadmin"
    The output should include "wal-g-archive=kbadmin"
    The output should not include "=postgres"
  End
End
