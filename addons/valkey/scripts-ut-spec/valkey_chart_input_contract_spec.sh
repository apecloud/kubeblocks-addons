# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey chart input contracts"
  cluster_chart="../../../addons-cluster/valkey"

  build_chart_dependency() {
    helm dependency build "${cluster_chart}" >/dev/null
  }
  BeforeAll "build_chart_dependency"

  reject_values() {
    helm template review "${cluster_chart}" "$@" >/dev/null
  }

  keep_contract() {
    rendered=$(helm template review .. --set extra.keepResource=true) || return 1
    printf '%s\n' "${rendered}" | awk '
      /^---$/ {
        if (kind == "ClusterDefinition" && keep) cluster_definition++
        if (kind == "ActionSet" && keep) action_set++
        if (kind == "BackupPolicyTemplate" && keep) backup_policy++
        kind=""; keep=0; next
      }
      /^kind: / {kind=$2}
      /^[[:space:]]+helm.sh\/resource-policy: keep$/ {keep=1}
      END {
        if (kind == "ClusterDefinition" && keep) cluster_definition++
        if (kind == "ActionSet" && keep) action_set++
        if (kind == "BackupPolicyTemplate" && keep) backup_policy++
        exit !(cluster_definition >= 1 && action_set >= 1 && backup_policy == 2)
      }
    '
  }

  quantity_contract() {
    rendered=$(helm template review "${cluster_chart}" \
      --set memory=512Mi \
      --set storage=20Gi \
      --set sentinel.memory=768Mi \
      --set sentinel.storage=6Gi) || return 1
    printf '%s\n' "${rendered}" | grep -q 'memory: "512Mi"' &&
      printf '%s\n' "${rendered}" | grep -q 'storage: 20Gi' &&
      printf '%s\n' "${rendered}" | grep -q 'memory: "768Mi"' &&
      printf '%s\n' "${rendered}" | grep -q 'storage: 6Gi' &&
      ! printf '%s\n' "${rendered}" | grep -Eq 'MiGi|GiGi'
  }

  legacy_numeric_quantity_contract() {
    rendered=$(helm template review "${cluster_chart}" \
      --set memory=1 \
      --set storage=20 \
      --set sentinel.memory=1 \
      --set sentinel.storage=5) || return 1
    printf '%s\n' "${rendered}" | grep -q 'memory: "1Gi"' &&
      printf '%s\n' "${rendered}" | grep -q 'storage: 20Gi'
  }

  It "rejects simultaneous NodePort and LoadBalancer exposure"
    When call reject_values --set nodePortEnabled=true --set loadBalancerEnabled=true
    The status should be failure
    The stderr should include "not"
  End

  It "rejects a partial data custom-secret pair"
    When call reject_values --set customSecretName=my-secret
    The status should be failure
    The stderr should include "oneOf"
  End

  It "rejects a partial Sentinel custom-secret pair"
    When call reject_values --set sentinel.customSecretNamespace=default
    The status should be failure
    The stderr should include "oneOf"
  End

  It "renders Kubernetes quantity strings without doubling units"
    When call quantity_contract
    The status should be success
  End

  It "preserves legacy numeric Gi inputs"
    When call legacy_numeric_quantity_contract
    The status should be success
  End

  It "rejects replication mode with only one data replica"
    When call reject_values --set mode=replication --set replicas=1
    The status should be failure
    The stderr should include "want 2"
  End

  It "renders valid paired secrets and one exposure mode"
    When call helm template review "${cluster_chart}" \
      --set mode=replication \
      --set nodePortEnabled=true \
      --set customSecretName=data-secret \
      --set customSecretNamespace=default \
      --set sentinel.customSecretName=sentinel-secret \
      --set sentinel.customSecretNamespace=default
    The status should be success
    The stdout should include "serviceType: NodePort"
    The stdout should include "name: data-secret"
    The stdout should include "name: sentinel-secret"
  End

  It "retains the complete definition and backup contract graph"
    When call keep_contract
    The status should be success
  End
End
