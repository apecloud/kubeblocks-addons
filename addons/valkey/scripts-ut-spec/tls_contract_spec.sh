# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey TLS verification contract"
  data_cmpd="../templates/cmpd.yaml"
  sentinel_cmpd="../templates/cmpd-valkey-sentinel.yaml"
  sentinel_start="../scripts/valkey-sentinel-start.sh"
  cluster_secret="../../../addons-cluster/valkey/templates/secret.yaml"

  It "builds VALKEY_CLI_TLS_ARGS with CA verification, not --insecure"
    When call grep -F -- "--tls --cacert" "${data_cmpd}" "${sentinel_cmpd}"
    The status should be success
    The stdout should include "cmpd.yaml"
    The stdout should include "cmpd-valkey-sentinel.yaml"
  End

  It "does not skip certificate verification in the CMPD CLI args"
    When call grep -F -- "--insecure" "${data_cmpd}" "${sentinel_cmpd}"
    The status should be failure
  End

  It "does not skip certificate verification in the sentinel start script"
    When call grep -F -- "--insecure" "${sentinel_start}"
    The status should be failure
  End

  It "issues the self-signed cert with per-component pod-FQDN wildcard SANs"
    # "*.svc.cluster.local" only matches ONE label; pod FQDNs have three
    # (pod.comp-headless.ns), so per-component wildcards are required for
    # verification to ever succeed.
    When call grep -F -- "-headless.%s.svc.cluster.local" "${cluster_secret}"
    The status should be success
    The stdout should include "valkey-headless"
    The stdout should include "valkey-sentinel-headless"
  End

  It "keeps --insecure in DataProtection jobs only, with the execution-face rationale"
    # Backup/restore jobs do not mount the TLS volume, so they cannot verify;
    # that exception must stay documented where it is used.
    When call grep -l "no CA file is available in this execution face" ../dataprotection/backup.sh ../dataprotection/post-restore-sentinel.sh
    The status should be success
    The stdout should include "backup.sh"
    The stdout should include "post-restore-sentinel.sh"
  End
End
