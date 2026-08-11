#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION_TEMPLATE="$ADDON_DIR/templates/remove_ag_upgrade_migration.yaml"
MIGRATION_SCRIPT="$ADDON_DIR/scripts/remove_ag_upgrade_migration.sh"
pass=0
fail=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

contains() {
  local pattern="$1"
  local file="$2"
  grep -Fq -- "$pattern" "$file"
}

hook_weights_are_ordered() {
  grep -Fq -- '"helm.sh/hook-weight": "-40"' "$MIGRATION_TEMPLATE" &&
    grep -Fq -- '"helm.sh/hook-weight": "-30"' "$MIGRATION_TEMPLATE" &&
    grep -Fq -- '"helm.sh/hook-weight": "-20"' "$MIGRATION_TEMPLATE" &&
    grep -Fq -- '"helm.sh/hook-weight": "-10"' "$MIGRATION_TEMPLATE"
}

rbac_verbs_are_scoped() {
  grep -Fq -- "- get" "$MIGRATION_TEMPLATE" &&
    grep -Fq -- "- delete" "$MIGRATION_TEMPLATE" &&
    ! grep -Eq -- "- (create|patch|update|deletecollection|list|watch)$" "$MIGRATION_TEMPLATE"
}

cluster_role_authority_is_exact() {
  local actual_authority
  local expected_authority
  local role_yaml
  local temp_dir

  role_yaml="$(
    awk '
      function emit_role() {
        if (is_role) {
          roles++
          printf "%s", document
        }
        document = ""
        is_role = 0
      }
      /^---$/ {
        emit_role()
        document = $0 ORS
        next
      }
      {
        document = document $0 ORS
        if ($0 == "kind: ClusterRole") {
          is_role = 1
        }
      }
      END {
        emit_role()
        if (roles != 1) {
          exit 1
        }
      }
    '
  )" || return 1

  temp_dir="$(mktemp -d)"
  mkdir -p "$temp_dir/chart/templates"
  printf '%s\n' \
    'apiVersion: v2' \
    'name: rbac-contract' \
    'version: 0.1.0' >"$temp_dir/chart/Chart.yaml"
  printf '%s\n' \
    '{{- $role := .Values.role | fromYaml -}}' \
    '{{- if ne (get $role "kind") "ClusterRole" }}{{ fail "expected one ClusterRole" }}{{ end -}}' \
    '{{- if hasKey $role "aggregationRule" }}{{ fail "aggregationRule is forbidden" }}{{ end -}}' \
    '{{- dict "rules" (get $role "rules") | toJson }}' >"$temp_dir/chart/templates/authority.yaml"
  printf '%s' "$role_yaml" >"$temp_dir/role.yaml"

  actual_authority="$(
    helm template rbac-contract "$temp_dir/chart" \
      --set-file role="$temp_dir/role.yaml" 2>/dev/null |
      grep '^{"rules":'
  )" || {
    rm -rf "$temp_dir"
    return 1
  }
  rm -rf "$temp_dir"

  expected_authority='{"rules":[{"apiGroups":["operations.kubeblocks.io"],"resourceNames":["mssql-dynamic-remove-ag"],"resources":["opsdefinitions"],"verbs":["get","delete"]}]}'
  [[ "$actual_authority" == "$expected_authority" ]]
}

rendered_rbac_rule_is_exact() {
  helm template mssql "$ADDON_DIR" \
    --namespace mssql-rbac-contract \
    --show-only templates/remove_ag_upgrade_migration.yaml |
    cluster_role_authority_is_exact
}

migration_object_graph_is_exact() {
  local expected_namespace="${1:?expected namespace is required}"
  local actual_contract
  local rendered_yaml
  local temp_dir

  rendered_yaml="$(cat)"
  temp_dir="$(mktemp -d)"
  mkdir -p "$temp_dir/chart/templates"
  printf '%s\n' \
    'apiVersion: v2' \
    'name: migration-contract' \
    'version: 0.1.0' >"$temp_dir/chart/Chart.yaml"
  printf '%s' "$rendered_yaml" >"$temp_dir/rendered.yaml"

  if ! awk -v output_dir="$temp_dir" '
    function emit_document(path) {
      if (document == "") {
        return
      }
      documents++
      path = ""
      if (kind == "ServiceAccount") {
        service_accounts++
        path = output_dir "/service-account.yaml"
      } else if (kind == "ClusterRole") {
        cluster_roles++
        path = output_dir "/cluster-role.yaml"
      } else if (kind == "ClusterRoleBinding") {
        cluster_role_bindings++
        path = output_dir "/cluster-role-binding.yaml"
      } else if (kind == "Job") {
        jobs++
        path = output_dir "/job.yaml"
      } else {
        unknown_documents++
      }
      if (path != "") {
        printf "%s", document > path
        close(path)
      }
      document = ""
      kind = ""
    }
    /^---[[:space:]]*$/ {
      emit_document()
      next
    }
    {
      document = document $0 ORS
      if ($0 ~ /^kind:[[:space:]]*/) {
        kind = $0
        sub(/^kind:[[:space:]]*/, "", kind)
      }
    }
    END {
      emit_document()
      if (documents != 4 ||
          service_accounts != 1 ||
          cluster_roles != 1 ||
          cluster_role_bindings != 1 ||
          jobs != 1 ||
          unknown_documents != 0) {
        exit 1
      }
    }
  ' "$temp_dir/rendered.yaml"; then
    rm -rf "$temp_dir"
    return 1
  fi

  printf '%s\n' \
    '{{- $sa := .Values.serviceAccount | fromYaml -}}' \
    '{{- $role := .Values.clusterRole | fromYaml -}}' \
    '{{- $binding := .Values.clusterRoleBinding | fromYaml -}}' \
    '{{- $job := .Values.job | fromYaml -}}' \
    '{{- if ne (get $sa "apiVersion") "v1" }}{{ fail "unexpected ServiceAccount apiVersion" }}{{ end -}}' \
    '{{- if ne (get $sa "kind") "ServiceAccount" }}{{ fail "expected ServiceAccount" }}{{ end -}}' \
    '{{- if ne (get $role "apiVersion") "rbac.authorization.k8s.io/v1" }}{{ fail "unexpected ClusterRole apiVersion" }}{{ end -}}' \
    '{{- if ne (get $role "kind") "ClusterRole" }}{{ fail "expected ClusterRole" }}{{ end -}}' \
    '{{- if ne (get $binding "apiVersion") "rbac.authorization.k8s.io/v1" }}{{ fail "unexpected ClusterRoleBinding apiVersion" }}{{ end -}}' \
    '{{- if ne (get $binding "kind") "ClusterRoleBinding" }}{{ fail "expected ClusterRoleBinding" }}{{ end -}}' \
    '{{- if ne (get $job "apiVersion") "batch/v1" }}{{ fail "unexpected Job apiVersion" }}{{ end -}}' \
    '{{- if ne (get $job "kind") "Job" }}{{ fail "expected Job" }}{{ end -}}' \
    '{{- $saMeta := get $sa "metadata" -}}' \
    '{{- $roleMeta := get $role "metadata" -}}' \
    '{{- $bindingMeta := get $binding "metadata" -}}' \
    '{{- $jobMeta := get $job "metadata" -}}' \
    '{{- $expectedNamespace := required "expected namespace is required" .Values.expectedNamespace -}}' \
    '{{- if or (empty (get $saMeta "name")) (empty (get $saMeta "namespace")) }}{{ fail "ServiceAccount identity is empty" }}{{ end -}}' \
    '{{- if empty (get $roleMeta "name") }}{{ fail "ClusterRole identity is empty" }}{{ end -}}' \
    '{{- if empty (get $bindingMeta "name") }}{{ fail "ClusterRoleBinding identity is empty" }}{{ end -}}' \
    '{{- if or (empty (get $jobMeta "name")) (empty (get $jobMeta "namespace")) }}{{ fail "Job identity is empty" }}{{ end -}}' \
    '{{- if ne (get $saMeta "namespace") $expectedNamespace }}{{ fail "ServiceAccount namespace differs from the release namespace" }}{{ end -}}' \
    '{{- if not (empty (get $roleMeta "namespace")) }}{{ fail "ClusterRole must not have a namespace" }}{{ end -}}' \
    '{{- if not (empty (get $bindingMeta "namespace")) }}{{ fail "ClusterRoleBinding must not have a namespace" }}{{ end -}}' \
    '{{- if ne (get $jobMeta "namespace") $expectedNamespace }}{{ fail "Job namespace differs from the release namespace" }}{{ end -}}' \
    '{{- $deletePolicy := "before-hook-creation,hook-succeeded" -}}' \
    '{{- $saAnnotations := dict "helm.sh/hook" "pre-upgrade" "helm.sh/hook-weight" "-40" "helm.sh/hook-delete-policy" $deletePolicy -}}' \
    '{{- $roleAnnotations := dict "helm.sh/hook" "pre-upgrade" "helm.sh/hook-weight" "-30" "helm.sh/hook-delete-policy" $deletePolicy -}}' \
    '{{- $bindingAnnotations := dict "helm.sh/hook" "pre-upgrade" "helm.sh/hook-weight" "-20" "helm.sh/hook-delete-policy" $deletePolicy -}}' \
    '{{- $jobAnnotations := dict "helm.sh/hook" "pre-upgrade" "helm.sh/hook-weight" "-10" "helm.sh/hook-delete-policy" $deletePolicy -}}' \
    '{{- if ne (toJson (get $saMeta "annotations")) (toJson $saAnnotations) }}{{ fail "unexpected ServiceAccount hook annotations" }}{{ end -}}' \
    '{{- if ne (toJson (get $roleMeta "annotations")) (toJson $roleAnnotations) }}{{ fail "unexpected ClusterRole hook annotations" }}{{ end -}}' \
    '{{- if ne (toJson (get $bindingMeta "annotations")) (toJson $bindingAnnotations) }}{{ fail "unexpected ClusterRoleBinding hook annotations" }}{{ end -}}' \
    '{{- if ne (toJson (get $jobMeta "annotations")) (toJson $jobAnnotations) }}{{ fail "unexpected Job hook annotations" }}{{ end -}}' \
    '{{- $expectedRoleRef := dict "apiGroup" "rbac.authorization.k8s.io" "kind" (get $role "kind") "name" (get $roleMeta "name") -}}' \
    '{{- if ne (toJson (get $binding "roleRef")) (toJson $expectedRoleRef) }}{{ fail "binding roleRef does not identify the rendered ClusterRole" }}{{ end -}}' \
    '{{- $expectedSubject := dict "kind" (get $sa "kind") "name" (get $saMeta "name") "namespace" $expectedNamespace -}}' \
    '{{- if ne (toJson (get $binding "subjects")) (toJson (list $expectedSubject)) }}{{ fail "binding subject does not identify the rendered ServiceAccount" }}{{ end -}}' \
    '{{- $podSpec := get (get (get $job "spec") "template") "spec" -}}' \
    '{{- if ne (get $podSpec "serviceAccountName") (get $saMeta "name") }}{{ fail "Job does not use the rendered ServiceAccount" }}{{ end -}}' \
    'contract: ok' >"$temp_dir/chart/templates/contract.yaml"

  actual_contract="$(
    helm template migration-contract "$temp_dir/chart" \
      --set-file serviceAccount="$temp_dir/service-account.yaml" \
      --set-file clusterRole="$temp_dir/cluster-role.yaml" \
      --set-file clusterRoleBinding="$temp_dir/cluster-role-binding.yaml" \
      --set-file job="$temp_dir/job.yaml" \
      --set-string expectedNamespace="$expected_namespace" |
      grep '^contract: ok$'
  )" || {
    rm -rf "$temp_dir"
    return 1
  }
  rm -rf "$temp_dir"

  [[ "$actual_contract" == "contract: ok" ]]
}

rendered_migration_object_graph_is_exact() {
  helm template mssql "$ADDON_DIR" \
    --namespace mssql-rbac-contract \
    --show-only templates/remove_ag_upgrade_migration.yaml |
    migration_object_graph_is_exact mssql-rbac-contract
}

cluster_admin_role_ref_is_rejected() {
  local mutated_render

  mutated_render="$(
    helm template mssql "$ADDON_DIR" \
      --namespace mssql-rbac-contract \
      --show-only templates/remove_ag_upgrade_migration.yaml |
      awk '
        /^---[[:space:]]*$/ {
          in_binding = 0
          in_role_ref = 0
        }
        /^kind: ClusterRoleBinding$/ {
          in_binding = 1
        }
        in_binding && /^roleRef:$/ {
          in_role_ref = 1
        }
        in_binding && in_role_ref && /^  name:/ {
          print "  name: cluster-admin"
          mutations++
          in_role_ref = 0
          next
        }
        {
          print
        }
        END {
          if (mutations != 1) {
            exit 1
          }
        }
      '
  )" || return 1

  ! printf '%s\n' "$mutated_render" |
    migration_object_graph_is_exact mssql-rbac-contract 2>/dev/null
}

wrong_release_namespace_is_rejected() {
  local mutated_render

  mutated_render="$(
    helm template mssql "$ADDON_DIR" \
      --namespace mssql-rbac-contract \
      --show-only templates/remove_ag_upgrade_migration.yaml |
      awk '
        /^[[:space:]]+namespace:[[:space:]]*/ {
          sub(/namespace:[[:space:]].*$/, "namespace: default")
          mutations++
        }
        {
          print
        }
        END {
          if (mutations != 3) {
            exit 1
          }
        }
      '
  )" || return 1

  ! printf '%s\n' "$mutated_render" |
    migration_object_graph_is_exact mssql-rbac-contract 2>/dev/null
}

cluster_scoped_namespace_is_rejected() {
  local target_kind="${1:?target kind is required}"
  local mutated_render

  mutated_render="$(
    helm template mssql "$ADDON_DIR" \
      --namespace mssql-rbac-contract \
      --show-only templates/remove_ag_upgrade_migration.yaml |
      awk -v target_kind="$target_kind" '
        $0 == "kind: " target_kind {
          in_target = 1
        }
        in_target && $0 == "metadata:" {
          print
          print "  \"namespace\": mssql-rbac-contract"
          mutations++
          in_target = 0
          next
        }
        {
          print
        }
        END {
          if (mutations != 1) {
            exit 1
          }
        }
      '
  )" || return 1

  ! printf '%s\n' "$mutated_render" |
    migration_object_graph_is_exact mssql-rbac-contract 2>/dev/null
}

cluster_role_namespace_is_rejected() {
  cluster_scoped_namespace_is_rejected ClusterRole
}

cluster_role_binding_namespace_is_rejected() {
  cluster_scoped_namespace_is_rejected ClusterRoleBinding
}

flow_style_extra_rbac_rule_is_rejected() {
  ! cluster_role_authority_is_exact <<'YAML'
---
kind: ClusterRole
rules:
  - apiGroups:
      - operations.kubeblocks.io
    resources:
      - opsdefinitions
    resourceNames:
      - mssql-dynamic-remove-ag
    verbs:
      - get
      - delete
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get"]
YAML
}

aggregation_rule_is_rejected() {
  ! cluster_role_authority_is_exact <<'YAML'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mssql-remove-ag-migration
aggregationRule:
  clusterRoleSelectors:
    - matchLabels:
        rbac.example.com/aggregate-to-remove-ag: "true"
rules:
  - apiGroups:
      - operations.kubeblocks.io
    resources:
      - opsdefinitions
    resourceNames:
      - mssql-dynamic-remove-ag
    verbs:
      - get
      - delete
YAML
}

run_migration_with_fake_kubectl() {
  local mode="$1"
  local expected_rc="$2"
  local expected_delete_count="$3"
  local expected_get_count="$4"
  local temp_dir
  local actual_rc
  local actual_delete_count
  local actual_get_count
  local service_host="${5:-10.96.2.214}"
  local expected_server="${6:-https://10.96.2.214:443}"
  temp_dir="$(mktemp -d)"
  mkdir -p "$temp_dir/serviceaccount"
  printf '%s\n' "test-token-value" >"$temp_dir/serviceaccount/token"
  printf '%s\n' "test-ca-value" >"$temp_dir/serviceaccount/ca.crt"

  case "$mode" in
    missing-service-host)
      service_host=""
      ;;
    missing-token)
      rm -f "$temp_dir/serviceaccount/token"
      ;;
    missing-ca)
      rm -f "$temp_dir/serviceaccount/ca.crt"
      ;;
  esac

  cat >"$temp_dir/kubectl" <<'FAKE_KUBECTL'
#!/usr/bin/env bash
set -euo pipefail

: "${KUBECONFIG:?}"
[[ -s "$KUBECONFIG" ]]
mode="$(stat -c '%a' "$KUBECONFIG" 2>/dev/null || stat -f '%Lp' "$KUBECONFIG")"
[[ "$mode" == "600" ]]
grep -Fq -- "server: \"$FAKE_EXPECTED_SERVER\"" "$KUBECONFIG"
grep -Fq -- "certificate-authority: \"$FAKE_SERVICE_ACCOUNT_DIR/ca.crt\"" "$KUBECONFIG"
grep -Fq -- "tokenFile: \"$FAKE_SERVICE_ACCOUNT_DIR/token\"" "$KUBECONFIG"
! grep -Fq -- "$FAKE_TOKEN_VALUE" "$KUBECONFIG"

printf '%s\n' "$*" >>"$FAKE_KUBECTL_LOG"
case "${1:-}" in
  delete)
    if [[ "$FAKE_KUBECTL_MODE" == "delete-fails" ]]; then
      exit 1
    fi
    exit 0
    ;;
  get)
    case "$FAKE_KUBECTL_MODE" in
      absent)
        exit 0
        ;;
      eventually-absent)
        count=0
        if [[ -f "$FAKE_KUBECTL_STATE" ]]; then
          count="$(<"$FAKE_KUBECTL_STATE")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" >"$FAKE_KUBECTL_STATE"
        if [[ "$count" -lt 3 ]]; then
          printf '%s\n' "opsdefinition.operations.kubeblocks.io/mssql-dynamic-remove-ag"
        fi
        exit 0
        ;;
      object-persists)
        printf '%s\n' "opsdefinition.operations.kubeblocks.io/mssql-dynamic-remove-ag"
        exit 0
        ;;
      get-fails)
        echo "Unable to connect to the server: i/o timeout" >&2
        exit 2
        ;;
    esac
    exit 2
    ;;
esac
exit 2
FAKE_KUBECTL
  chmod +x "$temp_dir/kubectl"

  cat >"$temp_dir/sleep" <<'FAKE_SLEEP'
#!/usr/bin/env bash
exit 0
FAKE_SLEEP
  chmod +x "$temp_dir/sleep"

  set +e
  PATH="$temp_dir:$PATH" \
    FAKE_KUBECTL_MODE="$mode" \
    FAKE_KUBECTL_LOG="$temp_dir/kubectl.log" \
    FAKE_KUBECTL_STATE="$temp_dir/kubectl.state" \
    FAKE_SERVICE_ACCOUNT_DIR="$temp_dir/serviceaccount" \
    FAKE_TOKEN_VALUE="test-token-value" \
    FAKE_EXPECTED_SERVER="$expected_server" \
    KUBERNETES_SERVICE_HOST="$service_host" \
    KUBERNETES_SERVICE_PORT_HTTPS="443" \
    REMOVE_AG_SERVICE_ACCOUNT_DIR="$temp_dir/serviceaccount" \
    TMPDIR="$temp_dir" \
    sh "$MIGRATION_SCRIPT" >"$temp_dir/stdout" 2>"$temp_dir/stderr"
  actual_rc=$?
  set -e

  if [[ "$actual_rc" -ne "$expected_rc" ]]; then
    rm -rf "$temp_dir"
    return 1
  fi

  actual_delete_count="$(grep -c '^delete ' "$temp_dir/kubectl.log" 2>/dev/null || true)"
  if [[ "$actual_delete_count" -ne "$expected_delete_count" ]]; then
    rm -rf "$temp_dir"
    return 1
  fi
  actual_get_count="$(grep -c '^get ' "$temp_dir/kubectl.log" 2>/dev/null || true)"
  if [[ "$actual_get_count" -ne "$expected_get_count" ]]; then
    rm -rf "$temp_dir"
    return 1
  fi
  if [[ "$expected_delete_count" -gt 0 ]]; then
    contains \
      "delete opsdefinition.operations.kubeblocks.io mssql-dynamic-remove-ag --ignore-not-found=true --wait=false --request-timeout=10s" \
      "$temp_dir/kubectl.log" || {
      rm -rf "$temp_dir"
      return 1
    }
  fi
  if [[ "$expected_get_count" -gt 0 ]]; then
    contains \
      "get opsdefinition.operations.kubeblocks.io mssql-dynamic-remove-ag --ignore-not-found=true --request-timeout=3s -o name" \
      "$temp_dir/kubectl.log" || {
      rm -rf "$temp_dir"
      return 1
    }
  fi

  if [[ "$expected_rc" -eq 0 ]]; then
    contains "Legacy OpsDefinition is absent: mssql-dynamic-remove-ag" "$temp_dir/stdout" || {
      rm -rf "$temp_dir"
      return 1
    }
  elif contains "Legacy OpsDefinition is absent:" "$temp_dir/stdout"; then
    rm -rf "$temp_dir"
    return 1
  fi
  if grep -Fq -- "test-token-value" \
    "$temp_dir/stdout" "$temp_dir/stderr" "$temp_dir/kubectl.log" 2>/dev/null; then
    rm -rf "$temp_dir"
    return 1
  fi
  if find "$temp_dir" -name 'mssql-remove-ag-kubeconfig.*' -print -quit | grep -q .; then
    rm -rf "$temp_dir"
    return 1
  fi

  rm -rf "$temp_dir"
}

check "upgrade migration template exists" test -f "$MIGRATION_TEMPLATE"
check "upgrade migration script exists" test -f "$MIGRATION_SCRIPT"
check "migration runs only as a pre-upgrade hook" \
  contains '"helm.sh/hook": pre-upgrade' "$MIGRATION_TEMPLATE"
check "migration hook resources clean up after success" \
  contains '"helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded' "$MIGRATION_TEMPLATE"
check "all four migration resources are pre-upgrade hooks" \
  test "$(grep -Fc -- '"helm.sh/hook": pre-upgrade' "$MIGRATION_TEMPLATE")" -eq 4
check "hook weights order service account, RBAC, then Job" \
  hook_weights_are_ordered
check "RBAC is limited to the removed OpsDefinition name" \
  contains "resourceNames:" "$MIGRATION_TEMPLATE"
check "RBAC names only mssql-dynamic-remove-ag" \
  contains "- mssql-dynamic-remove-ag" "$MIGRATION_TEMPLATE"
check "RBAC grants get and delete only" \
  rbac_verbs_are_scoped
check "rendered RBAC rule is the exact migration authority tuple" \
  rendered_rbac_rule_is_exact
check "RBAC oracle rejects a second flow-style rule" \
  flow_style_extra_rbac_rule_is_rejected
check "RBAC oracle rejects ClusterRole aggregation" \
  aggregation_rule_is_rejected
check "rendered migration objects form one exact RBAC authority graph" \
  rendered_migration_object_graph_is_exact
check "RBAC graph oracle rejects a cluster-admin roleRef" \
  cluster_admin_role_ref_is_rejected
check "RBAC graph oracle rejects a coordinated wrong release namespace" \
  wrong_release_namespace_is_rejected
check "RBAC graph oracle rejects a namespaced ClusterRole" \
  cluster_role_namespace_is_rejected
check "RBAC graph oracle rejects a namespaced ClusterRoleBinding" \
  cluster_role_binding_namespace_is_rejected
check "migration Job executes the checked-in script" \
  contains '.Files.Get "scripts/remove_ag_upgrade_migration.sh"' "$MIGRATION_TEMPLATE"
check "migration writes the exact IPv4 API server" \
  run_migration_with_fake_kubectl absent 0 1 1
check "migration writes the exact bracketed IPv6 API server" \
  run_migration_with_fake_kubectl absent 0 1 1 "fd00::1" "https://[fd00::1]:443"
check "migration polls the exact name until deletion converges" \
  run_migration_with_fake_kubectl eventually-absent 0 1 3
check "migration fails closed when delete fails" \
  run_migration_with_fake_kubectl delete-fails 1 1 0
check "migration fails closed when the object persists" \
  run_migration_with_fake_kubectl object-persists 1 1 8
check "migration fails closed when absence verification errors" \
  run_migration_with_fake_kubectl get-fails 1 1 1
check "migration fails closed when Kubernetes service host is missing" \
  run_migration_with_fake_kubectl missing-service-host 1 0 0
check "migration fails closed when projected token is missing" \
  run_migration_with_fake_kubectl missing-token 1 0 0
check "migration fails closed when projected CA is missing" \
  run_migration_with_fake_kubectl missing-ca 1 0 0

echo
echo "Total: ${pass} passed, ${fail} failed"
test "$fail" -eq 0
