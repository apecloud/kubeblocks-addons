#!/usr/bin/env bash

set -euo pipefail

TARGET_MINIO_DEF="milvus-minio-1.2.0-alpha.1"
TARGET_MILVUS_DEF="milvus-standalone-1.2.0-alpha.1"
AFFECTED_MINIO_DEF="milvus-minio-1.2.0-alpha.0"
EXPECTED_PRECONDITION_DEADLINE_SECONDS="600"
KUBECTL="${KUBECTL:-kubectl}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-3}"
DESIRED_TIMEOUT_SECONDS="${DESIRED_TIMEOUT_SECONDS:-900}"
READY_TIMEOUT_SECONDS="${READY_TIMEOUT_SECONDS:-600}"

usage() {
  cat >&2 <<'EOF'
Usage: recover-embedded-minio-credential.sh NAMESPACE CLUSTER [OPSREQUEST]

Run this after creating the Upgrade OpsRequest shipped with Milvus addon
1.2.0-alpha.1. The script waits for the alpha.1 desired MinIO contract, then
replaces only the stale MinIO Pod if it is still on the affected alpha.0
definition. It never deletes Secrets or PVCs.
EOF
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

is_dns_label() {
  [[ "$1" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] && ((${#1} <= 63))
}

require_uint() {
  [[ "$2" =~ ^[0-9]+$ ]] || fail "$1 must be a non-negative integer"
}

[[ $# -eq 2 || $# -eq 3 ]] || {
  usage
  exit 64
}

namespace="$1"
cluster="$2"
opsrequest="${3:-${cluster}-minio-root-migrate}"
component="${cluster}-minio"
instanceset="${cluster}-minio"
root_secret="${cluster}-minio-account-root"
selector="app.kubernetes.io/instance=${cluster},apps.kubeblocks.io/component-name=minio"

is_dns_label "${namespace}" || fail "namespace is not a DNS label: ${namespace}"
is_dns_label "${cluster}" || fail "cluster is not a DNS label: ${cluster}"
is_dns_label "${opsrequest}" || fail "OpsRequest is not a DNS label: ${opsrequest}"
require_uint POLL_INTERVAL_SECONDS "${POLL_INTERVAL_SECONDS}"
require_uint DESIRED_TIMEOUT_SECONDS "${DESIRED_TIMEOUT_SECONDS}"
require_uint READY_TIMEOUT_SECONDS "${READY_TIMEOUT_SECONDS}"
((DESIRED_TIMEOUT_SECONDS > 0)) || fail "DESIRED_TIMEOUT_SECONDS must be greater than zero"
((READY_TIMEOUT_SECONDS > 0)) || fail "READY_TIMEOUT_SECONDS must be greater than zero"

command -v "${KUBECTL}" >/dev/null 2>&1 || fail "kubectl command is not executable: ${KUBECTL}"

validate_migration_contract() {
  local ops_cluster ops_type precondition_deadline force minio_def milvus_def
  ops_cluster=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
    -o jsonpath='{.spec.clusterName}' 2>/dev/null || true)
  ops_type=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
    -o jsonpath='{.spec.type}' 2>/dev/null || true)
  precondition_deadline=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
    -o jsonpath='{.spec.preConditionDeadlineSeconds}' 2>/dev/null || true)
  force=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
    -o jsonpath='{.spec.force}' 2>/dev/null || true)
  minio_def=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
    -o jsonpath='{.spec.upgrade.components[?(@.componentName=="minio")].componentDefinitionName}' 2>/dev/null || true)
  milvus_def=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
    -o jsonpath='{.spec.upgrade.components[?(@.componentName=="milvus")].componentDefinitionName}' 2>/dev/null || true)

  [[ "${ops_cluster}" == "${cluster}" ]] ||
    fail "OpsRequest cluster mismatch: expected ${cluster}, got ${ops_cluster:-missing}"
  [[ "${ops_type}" == "Upgrade" ]] ||
    fail "OpsRequest type mismatch: expected Upgrade, got ${ops_type:-missing}"
  [[ "${precondition_deadline}" == "${EXPECTED_PRECONDITION_DEADLINE_SECONDS}" ]] ||
    fail "OpsRequest precondition deadline mismatch: expected ${EXPECTED_PRECONDITION_DEADLINE_SECONDS}, got ${precondition_deadline:-missing}"
  [[ -z "${force}" || "${force}" == "false" ]] ||
    fail "OpsRequest must not use force to bypass the Cluster phase safety gate"
  [[ "${minio_def}" == "${TARGET_MINIO_DEF}" ]] ||
    fail "OpsRequest MinIO definition mismatch: expected ${TARGET_MINIO_DEF}, got ${minio_def:-missing}"
  [[ "${milvus_def}" == "${TARGET_MILVUS_DEF}" ]] ||
    fail "OpsRequest Milvus definition mismatch: expected ${TARGET_MILVUS_DEF}, got ${milvus_def:-missing}"
  printf 'opsrequest-contract=valid,name=%s,precondition=%s,force=false\n' \
    "${opsrequest}" "${precondition_deadline}"
}

wait_for_desired_contract() {
  local deadline first="" last="" ops_phase cluster_phase comp_def template_def credential_shape current
  deadline=$(($(date +%s) + DESIRED_TIMEOUT_SECONDS))

  while (($(date +%s) <= deadline)); do
    ops_phase=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    cluster_phase=$("${KUBECTL}" -n "${namespace}" get cluster "${cluster}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    case "${ops_phase}" in
      Failed|Cancelled|Aborted)
        fail "OpsRequest reached ${ops_phase} while waiting for desired contract; cluster=${cluster_phase:-missing}"
        ;;
    esac
    comp_def=$("${KUBECTL}" -n "${namespace}" get component "${component}" \
      -o jsonpath='{.spec.compDef}' 2>/dev/null || true)
    template_def=$("${KUBECTL}" -n "${namespace}" get instanceset "${instanceset}" \
      -o jsonpath='{.spec.template.metadata.labels.app\.kubernetes\.io/component}' 2>/dev/null || true)
    credential_shape=$("${KUBECTL}" -n "${namespace}" get secret "${root_secret}" \
      -o jsonpath='{.data.username}{"|"}{.data.password}' 2>/dev/null || true)
    current="ops=${ops_phase:-missing},cluster=${cluster_phase:-missing},component=${comp_def},template=${template_def},credential=$([[ "${credential_shape}" == ?*'|'?* ]] && printf non-empty || printf missing)"
    [[ -n "${first}" ]] || first="${current}"
    last="${current}"

    if [[ "${comp_def}" == "${TARGET_MINIO_DEF}" &&
          "${template_def}" == "${TARGET_MINIO_DEF}" &&
          "${credential_shape}" == ?*'|'?* ]]; then
      printf 'desired-contract=ready,first=%s,last=%s\n' "${first}" "${last}"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done

  fail "desired contract did not converge within ${DESIRED_TIMEOUT_SECONDS}s; first=${first}; last=${last}"
}

one_minio_pod() {
  local names count
  names=$("${KUBECTL}" -n "${namespace}" get pods -l "${selector}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  count=$(printf '%s\n' "${names}" | awk 'NF { count++ } END { print count + 0 }')
  [[ "${count}" == "1" ]] || fail "expected exactly one MinIO Pod, found ${count}"
  printf '%s\n' "${names}" | awk 'NF { print; exit }'
}

pod_uid() {
  "${KUBECTL}" -n "${namespace}" get pod "$1" -o jsonpath='{.metadata.uid}'
}

pod_definition() {
  "${KUBECTL}" -n "${namespace}" get pod "$1" \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/component}'
}

pod_ready() {
  "${KUBECTL}" -n "${namespace}" get pod "$1" \
    -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
}

pod_controller_owner() {
  "${KUBECTL}" -n "${namespace}" get pod "$1" \
    -o jsonpath='{.metadata.ownerReferences[?(@.controller==true)].kind}{"|"}{.metadata.ownerReferences[?(@.controller==true)].name}'
}

wait_for_replacement() {
  local old_uid="$1" require_new_uid="$2" deadline first="" last="" pod uid definition ready current
  deadline=$(($(date +%s) + READY_TIMEOUT_SECONDS))

  while (($(date +%s) <= deadline)); do
    pod=$(one_minio_pod 2>/dev/null || true)
    if [[ -n "${pod}" ]]; then
      uid=$(pod_uid "${pod}" 2>/dev/null || true)
      definition=$(pod_definition "${pod}" 2>/dev/null || true)
      ready=$(pod_ready "${pod}" 2>/dev/null || true)
      current="pod=${pod},uid=${uid},definition=${definition},ready=${ready}"
      [[ -n "${first}" ]] || first="${current}"
      last="${current}"
      if [[ "${definition}" == "${TARGET_MINIO_DEF}" && "${ready}" == "True" ]] &&
         { [[ "${require_new_uid}" == "false" ]] || [[ "${uid}" != "${old_uid}" ]]; }; then
        printf 'replacement-pod=%s,%s,Ready,first=%s,last=%s\n' "${pod}" "${uid}" "${first}" "${last}"
        return 0
      fi
    else
      current="pod=missing"
      [[ -n "${first}" ]] || first="${current}"
      last="${current}"
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done

  fail "replacement Pod did not become Ready within ${READY_TIMEOUT_SECONDS}s; first=${first}; last=${last}"
}

wait_for_operation_and_cluster() {
  local deadline first="" last="" ops_phase cluster_phase current
  deadline=$(($(date +%s) + READY_TIMEOUT_SECONDS))

  while (($(date +%s) <= deadline)); do
    ops_phase=$("${KUBECTL}" -n "${namespace}" get opsrequest "${opsrequest}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    cluster_phase=$("${KUBECTL}" -n "${namespace}" get cluster "${cluster}" \
      -o jsonpath='{.status.phase}' 2>/dev/null || true)
    current="ops=${ops_phase},cluster=${cluster_phase}"
    [[ -n "${first}" ]] || first="${current}"
    last="${current}"

    case "${ops_phase}" in
      Failed|Cancelled|Aborted)
        fail "OpsRequest reached ${ops_phase}; first=${first}; last=${last}"
        ;;
    esac
    if [[ "${ops_phase}" == "Succeed" && "${cluster_phase}" == "Running" ]]; then
      printf 'recovery=Succeed,cluster=Running,first=%s,last=%s\n' "${first}" "${last}"
      return 0
    fi
    sleep "${POLL_INTERVAL_SECONDS}"
  done

  fail "recovery did not converge within ${READY_TIMEOUT_SECONDS}s; first=${first}; last=${last}"
}

validate_migration_contract
wait_for_desired_contract

pod=$(one_minio_pod)
old_uid=$(pod_uid "${pod}")
definition=$(pod_definition "${pod}")

if [[ "${definition}" == "${TARGET_MINIO_DEF}" ]]; then
  printf 'replacement=not-needed,pod=%s,uid=%s\n' "${pod}" "${old_uid}"
  require_new_uid=false
else
  [[ "${definition}" == "${AFFECTED_MINIO_DEF}" ]] ||
    fail "refusing to replace Pod with unsupported definition: ${definition:-missing}"
  owner=$(pod_controller_owner "${pod}")
  [[ "${owner}" == "InstanceSet|${instanceset}" ]] ||
    fail "unexpected controller owner for ${pod}: ${owner}"
  printf 'stale-pod=%s,%s,definition=%s\n' "${pod}" "${old_uid}" "${definition}"
  "${KUBECTL}" -n "${namespace}" delete pod "${pod}" --wait=false
  require_new_uid=true
fi

wait_for_replacement "${old_uid}" "${require_new_uid}"
wait_for_operation_and_cluster
