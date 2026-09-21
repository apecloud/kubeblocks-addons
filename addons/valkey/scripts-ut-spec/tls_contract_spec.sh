# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey TLS verification contract"
  data_cmpd="../templates/cmpd.yaml"
  sentinel_cmpd="../templates/cmpd-valkey-sentinel.yaml"
  sentinel_start="../scripts/valkey-sentinel-start.sh"
  start_script="../scripts/valkey-start.sh"
  account_script="../scripts/valkey-account.sh"
  config_tpl="../config/valkey-config.tpl"
  config_constraint="../config/config-constraint.cue"
  paramsdef="../templates/paramsdef.yaml"
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

  It "keeps --insecure in job faces only, with the execution-face rationale"
    # Ops / backup / restore jobs do not mount the TLS volume, so they cannot
    # verify; that exception must stay documented where it is used.
    When call grep -l "no CA file is available in this execution face" \
      ../dataprotection/backup.sh ../dataprotection/restore-keys.sh \
      ../dataprotection/post-restore-sentinel.sh "${account_script}"
    The status should be success
    The stdout should include "backup.sh"
    The stdout should include "restore-keys.sh"
    The stdout should include "post-restore-sentinel.sh"
    The stdout should include "valkey-account.sh"
  End

  Describe "TLS lives in the start script, not in the config store (redis parity)"
    It "keeps no TLS directive in the config template"
      # Comments are allowed to name the directives; code lines are not.
      When call bash -c "grep -vE '^[[:space:]]*#' '${config_tpl}' | grep -E 'tls-port|tls-cert-file|tls-key-file|tls-ca-cert-file|tls-auth-clients|tls-replication'"
      The status should be failure
    End

    It "keeps no TLS parameter in the config constraint"
      # TLS must not be user-tunable: the paths have to match the volume
      # KubeBlocks mounts, so a config-store value could lock the cluster out.
      # ("tls-dynamic" is an unrelated endpoint-type value, hence the ^"tls-" key match.)
      When call grep -E '^[[:space:]]*"tls-' "${config_constraint}"
      The status should be failure
    End

    It "keeps tls-port out of the static parameters"
      When call grep -F -- "- tls-port" "${paramsdef}"
      The status should be failure
    End

    It "writes tls-port and the certificate material from the start script"
      When call grep -E "build_valkey_tls_config|tls-cert-file \\\$\\{tls_mount_path\\}/tls.crt|port 0" "${start_script}"
      The status should be success
      The stdout should include "build_valkey_tls_config"
      The stdout should include "port 0"
    End

    It "gates the TLS block on TLS_ENABLED, the redis-style switch"
      When call grep -F -- 'if [ "${TLS_ENABLED}" = "true" ]; then' "${start_script}"
      The status should be success
      The stdout should include "TLS_ENABLED"
    End

    It "gates the ops-pod TLS args on TLS_ENABLED too, never on a probe"
      When call grep -F -- 'if [ "${TLS_ENABLED:-false}" = "true" ]; then' "${account_script}"
      The status should be success
      The stdout should include "TLS_ENABLED"
    End

    It "injects TLS_ENABLED into the account ops pods"
      When call grep -F -- "envName: TLS_ENABLED" ../templates/opsdefinition-account.yaml
      The status should be success
      The stdout should include "TLS_ENABLED"
    End
  End
End
