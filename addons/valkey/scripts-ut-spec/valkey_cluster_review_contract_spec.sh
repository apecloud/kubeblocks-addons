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
      /livenessProbe:/ { live=1 }
      /readinessProbe:/ { probe="ready" }
      /valkey-cluster-ready.sh/ && probe=="ready" { ready=1 }
      END { exit !(!live && ready) }
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
  exclusive_primary_contract() {
    awk '
      /^  roles:/ { in_roles=1 }
      in_roles && /^    - name: primary$/ { in_primary=1; next }
      in_primary && /^      isExclusive: true$/ { found=1 }
      in_primary && /^    - name:/ { exit !found }
      END { exit !found }
    ' "${cmpd_file}"
  }
  parallel_provision_contract() {
    awk '
      /^  podManagementPolicy:/ {
        count++
        if ($2 == "Parallel") parallel++
      }
      END { exit !(count == 1 && parallel == 1) }
    ' "${cmpd_file}"
  }
  render_cluster_chart() {
    helm dependency build ../../../addons-cluster/valkey >/dev/null &&
      helm template review ../../../addons-cluster/valkey \
        --set mode=cluster --set podAntiAffinityEnabled=true
  }
  cluster_runtime_pull_policy_contract() {
    rendered=$(helm template review .. --set image.pullPolicy=Always) || return 1
    printf '%s\n' "${rendered}" | awk '
      /^---$/ { in_component_definition=0; in_cluster_definition=0; in_cluster_container=0 }
      /^kind: ComponentDefinition$/ { in_component_definition=1; next }
      in_component_definition && /^  name: valkey-cluster-/ { in_cluster_definition=1; next }
      in_cluster_definition && /^      - name: valkey-cluster$/ { in_cluster_container=1; next }
      in_cluster_container && /^        imagePullPolicy: ["'\'' ]*Always["'\'' ]*$/ { found=1 }
      END { exit !found }
    '
  }
  sentinel_runtime_pull_policy_contract() {
    rendered=$(helm template review .. --set image.pullPolicy=Always) || return 1
    printf '%s\n' "${rendered}" | awk '
      /^---$/ { in_component_definition=0; in_sentinel_definition=0; in_sentinel_container=0 }
      /^kind: ComponentDefinition$/ { in_component_definition=1; next }
      in_component_definition && /^  name: valkey-sentinel-/ { in_sentinel_definition=1; next }
      in_sentinel_definition && /^      - name: valkey-sentinel$/ { in_sentinel_container=1; next }
      in_sentinel_container && /^        imagePullPolicy: ["'\'' ]*Always["'\'' ]*$/ { found=1 }
      END { exit !found }
    '
  }
  standard_runtime_pull_policy_contract() {
    rendered=$(helm template review .. \
      --set image.pullPolicy=Always \
      --set metrics.image.pullPolicy=Always) || return 1
    printf '%s\n' "${rendered}" | awk '
      /^---$/ { in_component_definition=0; in_standard_definition=0; in_runtime_container=0 }
      /^kind: ComponentDefinition$/ { in_component_definition=1; next }
      in_component_definition && /^  name: valkey-[0-9]+$/ { in_standard_definition=1; next }
      in_standard_definition && /^      - name: (valkey|metrics)$/ { in_runtime_container=1; next }
      in_runtime_container && /^        imagePullPolicy:/ {
        count++
        if ($2 ~ /^["'\'' ]*Always["'\'' ]*$/) good++
        else bad=1
        in_runtime_container=0
      }
      END { exit !(count == 4 && good == 4 && !bad) }
    '
  }

  It "uses an explicit combined shard-to-FQDN map instead of individual suffix variables"
    When call combined_roster_contract
    The status should be success
    The stdout should include "strategy: combined"
  End

  It "uses cluster-aware readiness without channel-based liveness restarts"
    When call readiness_contract
    The status should be success
  End

  It "targets cluster datafile backups at primaries without secondary fallback"
    When call primary_backup_contract
    The status should be success
  End

  It "declares the primary role exclusive"
    When call exclusive_primary_contract
    The status should be success
  End

  It "creates every shard replica in parallel before cluster-gated readiness"
    When call parallel_provision_contract
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
    The stdout should include 'app.kubernetes.io/component: "valkey-cluster-shard"'
    The stdout should not include "apps.kubeblocks.io/sharding-name"
  End

  It "renders the mapped Always pull policy for the valkey-cluster runtime"
    When call cluster_runtime_pull_policy_contract
    The status should be success
  End

  It "renders the mapped Always pull policy for the valkey-sentinel runtime"
    When call sentinel_runtime_pull_policy_contract
    The status should be success
  End

  It "renders the mapped Always pull policy for every standard Valkey runtime container"
    When call standard_runtime_pull_policy_contract
    The status should be success
  End
End
