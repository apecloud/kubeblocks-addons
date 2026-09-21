# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey BackupPolicyTemplate contract"
  template_file="../templates/backuppolicytemplate.yaml"
  actionset_file="../templates/backupactionset.yaml"

  It "does not use ComponentDefinition var sources in BackupPolicyTemplate env"
    When call grep -E "componentVarRef|credentialVarRef" "${template_file}"
    The status should be failure
  End

  It "does not declare Sentinel cross-component env in BackupPolicyTemplate"
    When call grep -E "SENTINEL_POD_FQDN_LIST|SENTINEL_PASSWORD" "${template_file}"
    The status should be failure
  End

  It "does not wire the no-op Sentinel ACL restore job into ActionSet"
    When call grep -F "restore-sentinel-acl.sh" "${actionset_file}"
    The status should be failure
  End
End
