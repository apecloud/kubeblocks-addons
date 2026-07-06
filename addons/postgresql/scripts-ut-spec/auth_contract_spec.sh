# shellcheck shell=sh
# Contract tests pinning the authentication posture of the addon:
# - passwords are stored as SCRAM verifiers on every supported version
# - pgbouncer authenticates clients with SCRAM (an md5 auth_type cannot
#   verify accounts whose pg_shadow verifier is SCRAM)
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
    It "authenticates clients with scram-sha-256"
      When call grep -c "auth_type = scram-sha-256" ../config/pgbouncer-ini.tpl
      The output should eq 1
    End

    It "does not use md5 auth_type"
      When call grep -c "auth_type = md5" ../config/pgbouncer-ini.tpl
      The output should eq 0
      The status should be failure
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
