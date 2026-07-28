# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey cluster review contracts"
  cmpd_file="../templates/cmpd-valkey-cluster.yaml"
  bpt_file="../templates/backuppolicytemplate.yaml"
  cluster_config="../config/valkey-cluster-config.tpl"
  combined_roster_contract() {
    awk '
      /- name: ALL_SHARDS_COMPONENT_SHORT_NAMES/ { in_all_shards=1 }
      /- name: ALL_SHARDS_POD_FQDN_MAP/ { in_var=1 }
      in_var { print }
      in_var && /strategy: combined/ { combined=1 }
      in_all_shards && /requireAllComponentObjects: true/ { require_all++ }
      in_var && /keyValueDelimiter: "="/ { found_key=1 }
      in_var && /delimiter: ";"/ { found_delimiter=1 }
      in_var && found_key && found_delimiter && combined && require_all >= 2 { exit 0 }
      END { if (!(found_key && found_delimiter && combined && require_all >= 2)) exit 1 }
    ' "${cmpd_file}"
  }
  readiness_contract() {
    awk '
      /livenessProbe:/ { probe="live" }
      /readinessProbe:/ { probe="ready" }
      /valkey-ping.sh/ && probe=="live" { live=1 }
      /valkey-cluster-ready.sh/ && probe=="ready" { ready=1 }
      END { exit !(live && ready) }
    ' "${cmpd_file}"
  }
  primary_backup_contract() {
    awk '
      /name: valkey-cluster-backup-policy-template/ { cluster=1 }
      cluster && /^  target:/ { target=1; next }
      target && /^    role: primary$/ { primary=1 }
      target && /fallbackRole:/ { fallback=1 }
      cluster && /^  backupMethods:/ { exit !(primary && !fallback) }
      END { if (!cluster) exit 1 }
    ' "${bpt_file}"
  }
  render_cluster_chart() {
    helm dependency build ../../../addons-cluster/valkey >/dev/null &&
      helm template review ../../../addons-cluster/valkey \
        --set mode=cluster --set podAntiAffinityEnabled=true
  }

  It "uses an explicit combined shard-to-FQDN map instead of individual suffix variables"
    When call combined_roster_contract
    The status should be success
    The stdout should include "strategy: combined"
  End

  It "uses a cluster-aware readiness script while keeping liveness on PING"
    When call readiness_contract
    The status should be success
  End

  It "targets cluster datafile backups at primaries without secondary fallback"
    When call primary_backup_contract
    The status should be success
  End

  It "does not override Valkey's replica-validity safety default"
    When call grep -E '^cluster-replica-validity-factor[[:space:]]+0$' "${cluster_config}"
    The status should be failure
  End

  It "renders preferred anti-affinity for cluster shards when enabled"
    When call render_cluster_chart
    The status should be success
    The stdout should include "podAntiAffinity:"
    The stdout should include 'apps.kubeblocks.io/sharding-name: "shard"'
  End
End
