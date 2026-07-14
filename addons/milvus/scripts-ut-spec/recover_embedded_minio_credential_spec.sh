# shellcheck shell=bash

Describe "Milvus embedded MinIO credential recovery"
  setup() {
    tmpdir=$(mktemp -d -t milvus-minio-recovery-XXXXXX)
    state_dir="${tmpdir}/state"
    mkdir -p "${state_dir}"
    calls_file="${state_dir}/calls"
    fake_kubectl="${tmpdir}/kubectl"

    cat >"${fake_kubectl}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${FAKE_STATE_DIR}/calls"
if [[ "${1:-}" == "-n" ]]; then
  shift 2
fi

target_def="milvus-minio-1.2.0-alpha.1"
target_milvus_def="milvus-standalone-1.2.0-alpha.1"
deleted=false
[[ -f "${FAKE_STATE_DIR}/deleted" ]] && deleted=true
[[ "${START_TARGET:-false}" == "true" ]] && deleted=true

case "${1:-} ${2:-}" in
  "get component")
    printf '%s' "${target_def}"
    ;;
  "get instanceset")
    printf '%s' "${target_def}"
    ;;
  "get secret")
    printf '%s' 'cm9vdA==|cGFzc3dvcmQ='
    ;;
  "get pods")
    printf '%s\n' 'demo-minio-0'
    ;;
  "get pod")
    output="${*: -1}"
    case "${output}" in
      *metadata.uid*)
        if ${deleted}; then printf '%s' 'uid-new'; else printf '%s' 'uid-old'; fi
        ;;
      *app\\.kubernetes\\.io/component*)
        if ${deleted}; then printf '%s' "${target_def}"; else printf '%s' "${OLD_DEF:-milvus-minio-1.2.0-alpha.0}"; fi
        ;;
      *ownerReferences*)
        printf '%s' "${FAKE_OWNER_KIND:-InstanceSet}|demo-minio"
        ;;
      *status.conditions*)
        if ${deleted}; then printf '%s' 'True'; else printf '%s' 'False'; fi
        ;;
      *)
        printf 'unexpected pod query: %s\n' "${output}" >&2
        exit 64
        ;;
    esac
    ;;
  "delete pod")
    touch "${FAKE_STATE_DIR}/deleted"
    printf '%s\n' 'pod "demo-minio-0" deleted'
    ;;
  "get opsrequest")
    output="${*: -1}"
    case "${output}" in
      *spec.clusterName*) printf '%s' "${FAKE_OPS_CLUSTER:-demo}" ;;
      *spec.type*) printf '%s' 'Upgrade' ;;
      *componentName==\"minio\"*) printf '%s' "${target_def}" ;;
      *componentName==\"milvus\"*) printf '%s' "${target_milvus_def}" ;;
      *status.phase*) if ${deleted}; then printf '%s' 'Succeed'; else printf '%s' 'Running'; fi ;;
      *) printf 'unexpected OpsRequest query: %s\n' "${output}" >&2; exit 64 ;;
    esac
    ;;
  "get cluster")
    printf '%s' 'Running'
    ;;
  *)
    printf 'unexpected kubectl call: %s\n' "$*" >&2
    exit 64
    ;;
esac
EOF
    chmod +x "${fake_kubectl}"
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  run_recovery() {
    FAKE_STATE_DIR="${state_dir}" \
      KUBECTL="${fake_kubectl}" \
      POLL_INTERVAL_SECONDS=0 \
      DESIRED_TIMEOUT_SECONDS=2 \
      READY_TIMEOUT_SECONDS=2 \
      bash ../scripts/recover-embedded-minio-credential.sh demo demo demo-minio-root-migrate
  }

  run_already_target() {
    START_TARGET=true run_recovery
  }

  run_wrong_owner() {
    FAKE_OWNER_KIND=StatefulSet run_recovery
  }

  run_unknown_definition() {
    OLD_DEF=milvus-minio-9.9.9 run_recovery
  }

  run_wrong_opsrequest() {
    FAKE_OPS_CLUSTER=other-cluster run_recovery
  }

  It "replaces only the stale failed MinIO Pod after the desired alpha.1 contract is visible"
    When call run_recovery
    The status should be success
    The output should include "desired-contract=ready"
    The output should include "stale-pod=demo-minio-0,uid-old"
    The output should include "replacement-pod=demo-minio-0,uid-new,Ready"
    The output should include "recovery=Succeed,cluster=Running"
    The contents of file "${calls_file}" should include "delete pod demo-minio-0 --wait=false"
    The contents of file "${calls_file}" should not include "delete pvc"
    The contents of file "${calls_file}" should not include "delete secret"
  End

  It "is idempotent when the Pod already uses the target definition"
    When call run_already_target
    The status should be success
    The output should include "replacement=not-needed"
    The output should include "recovery=Succeed,cluster=Running"
    The contents of file "${calls_file}" should not include "delete pod"
  End

  It "fails closed instead of deleting a Pod not owned by the expected InstanceSet"
    When call run_wrong_owner
    The status should be failure
    The output should include "desired-contract=ready"
    The stderr should include "unexpected controller owner"
    The contents of file "${calls_file}" should not include "delete pod"
  End

  It "refuses to replace a Pod from an unrecognized definition"
    When call run_unknown_definition
    The status should be failure
    The output should include "opsrequest-contract=valid"
    The stderr should include "unsupported definition"
    The contents of file "${calls_file}" should not include "delete pod"
  End

  It "rejects an OpsRequest for another Cluster before inspecting or deleting Pods"
    When call run_wrong_opsrequest
    The status should be failure
    The stderr should include "OpsRequest cluster mismatch"
    The contents of file "${calls_file}" should not include "get pods"
    The contents of file "${calls_file}" should not include "delete pod"
  End
End
