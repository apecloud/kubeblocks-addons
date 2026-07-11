# shellcheck shell=sh
# Contract tests pinning the authentication posture of the addon:
# - passwords are stored as SCRAM verifiers on every supported version
# - pgbouncer keeps auth_type = md5, which is PgBouncer's DUAL-MODE setting:
#   when the secret fetched via auth_query is a SCRAM verifier it performs
#   SCRAM on the wire automatically. auth_type = scram-sha-256 would be
#   SCRAM-only (md5-hashed secrets unusable) and lock pre-upgrade accounts
#   out of the pooler path.
# - pg_hba keeps the dual-mode `md5` method so accounts created by older
#   addon versions (md5-stored) survive an upgrade, while SCRAM-stored
#   accounts automatically get SCRAM on the wire

Describe "postgresql authentication contract"

  Describe "password_encryption"
    check_password_encryption() {
      grep -L "password_encryption = 'scram-sha-256'" ../config/pg*-config.tpl
    }

    It "is scram-sha-256 in every version's config template"
      When call check_password_encryption
      The output should eq ""
      The status should be success
    End

    check_no_md5_storage() {
      grep -l "password_encryption = 'md5'" ../config/pg*-config.tpl
    }

    It "is not md5 in any version's config template"
      When call check_no_md5_storage
      The output should eq ""
      The status should be failure
    End
  End

  Describe "pgbouncer"
    It "keeps the dual-mode md5 auth_type (auto-SCRAM for SCRAM verifiers)"
      When call grep -c "^auth_type = md5" ../config/pgbouncer-ini.tpl
      The output should eq 1
    End

    It "does not pin SCRAM-only auth_type (would lock out md5-stored accounts)"
      When call grep -c "^auth_type = scram-sha-256" ../config/pgbouncer-ini.tpl
      The output should eq 0
      The status should be failure
    End

    It "keeps cmpd PGBOUNCER_AUTH_TYPE aligned with the ini dual-mode setting"
      When call grep -A1 "name: PGBOUNCER_AUTH_TYPE" ../templates/cmpd.yaml
      The output should include "value: md5"
    End
  End

  Describe "pg_hba"
    It "keeps the dual-mode md5 method for remote host access (upgrade compatibility)"
      When call grep -Ec "^    host +all +all +0\.0\.0\.0/0 +md5" ../templates/configmap.yaml
      The output should eq 1
    End

    It "does not open remote access with trust"
      When call grep -Ec "^    host +(all|replication) +all +(0\.0\.0\.0/0|::/0) +trust" ../templates/configmap.yaml
      The output should eq 0
      The status should be failure
    End
  End
End
