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

Describe "Cluster topology TLS boundary (v1: unsupported, TL ruling #valkey:557234f0)"
  # A `tls:` capability declaration WITHOUT the full runtime wiring
  # (TLS_ENABLED var, tls-port/plaintext-port swap, tls-cluster bus, CLI
  # flags) produced a SILENT PLAINTEXT cluster while the user believed TLS
  # was on. These contracts pin the v1 boundary: the cluster cmpd stays
  # tls-free until support lands as ONE complete, live-verified change.
  # Restoring any single piece alone must fail this spec.
  cluster_cmpd="../templates/cmpd-valkey-cluster.yaml"
  cluster_config="../config/valkey-cluster-config.tpl"
  data_cmpd="../templates/cmpd.yaml"
  chart_helpers="../../../addons-cluster/valkey/templates/_helpers.tpl"

  It "cluster cmpd declares NO tls capability"
    When call grep -E "^  tls:" "${cluster_cmpd}"
    The status should be failure
  End

  It "cluster cmpd defines NO TLS CLI args or TLS vars (no dead half-wiring)"
    When call grep -E "VALKEY_CLI_TLS_ARGS|TLS_ENABLED|TLS_MOUNT_PATH" "${cluster_cmpd}"
    The status should be failure
  End

  It "cluster config template renders NO tls directives"
    When call grep -E "^tls-|^port 0" "${cluster_config}"
    The status should be failure
  End

  It "the cluster chart refuses tlsEnable for mode=cluster (explicit, not silent)"
    When call grep -F "does not support TLS" "${chart_helpers}"
    The status should be success
    The stdout should include "tlsEnable must be false"
  End

  It "sentinel-mode data cmpd keeps its full TLS declaration (unaffected)"
    When call grep -E "^  tls:" "${data_cmpd}"
    The status should be success
    The stdout should include "tls:"
  End
End
