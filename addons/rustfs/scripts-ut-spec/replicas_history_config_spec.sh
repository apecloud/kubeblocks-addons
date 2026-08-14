# shellcheck shell=sh

Describe "RustFS replicas history ConfigMap contract"
  setup_case() {
    case_dir=$(mktemp -d -t rustfs-replicas-history-XXXXXX) || return $?
    mock_bin="${case_dir}/bin"
    call_log="${case_dir}/kubectl.calls"
    history_dir="${case_dir}/history"
    history_file="${history_dir}/RUSTFS_REPLICAS_HISTORY"
    mkdir -p "${mock_bin}" "${history_dir}" || return $?
    : >"${call_log}" || return $?

    cat >"${mock_bin}/kubectl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${KUBECTL_CALL_LOG}"

case "$*" in
  "get configmaps rustfs-rustfs-configuration -n test --ignore-not-found -o name")
    get_count_file="${KUBECTL_GET_COUNT_FILE}"
    get_count=$(cat "${get_count_file}")
    get_count=$((get_count + 1))
    printf '%s\n' "${get_count}" >"${get_count_file}"
    get_mode="${KUBECTL_GET_MODE:-present}"
    if [ "${get_count}" -gt 1 ] && [ -n "${KUBECTL_RECHECK_MODE:-}" ]; then
      get_mode="${KUBECTL_RECHECK_MODE}"
    fi
    case "${get_mode}" in
      present) printf '%s\n' 'configmap/rustfs-rustfs-configuration' ;;
      absent) : ;;
      fail) exit 41 ;;
      *) exit 46 ;;
    esac
    ;;
  "get configmaps rustfs-rustfs-configuration -n test -o jsonpath={.data.RUSTFS_REPLICAS_HISTORY}")
    [ "${KUBECTL_READ_MODE:-success}" = success ] || exit 42
    printf '%s' "${KUBECTL_READ_VALUE-[4]}"
    ;;
  "get configmaps rustfs-rustfs-configuration -n test -o jsonpath={.metadata.resourceVersion}{'\\t'}{.data.RUSTFS_REPLICAS_HISTORY}")
    case "${KUBECTL_READ_MODE:-success}" in
      success)
        if [ "${KUBECTL_PATCH_MODE:-success}" = race ] && [ "$(cat "${KUBECTL_RACE_PHASE_FILE}")" -gt 0 ]; then
          printf '2\t[4,12]'
        else
          printf '1\t%s' "${KUBECTL_READ_VALUE-[4]}"
        fi
        ;;
      malformed) printf '%s' "${KUBECTL_READ_VALUE-[4]}" ;;
      *) exit 42 ;;
    esac
    ;;
  "create -f -")
    cat >/dev/null
    [ "${KUBECTL_CREATE_MODE:-success}" = success ] || exit 43
    ;;
  "patch configmap rustfs-rustfs-configuration -n test --type strategic -p "*)
    case "${KUBECTL_PATCH_MODE:-success}" in
      success) : ;;
      race)
        case "$*" in
          *'"resourceVersion":"1"'*)
            printf '1\n' >"${KUBECTL_RACE_PHASE_FILE}"
            exit 44
            ;;
          *'"resourceVersion":"2"'*) : ;;
          *) : ;;
        esac
        ;;
      *) exit 44 ;;
    esac
    ;;
  *)
    printf 'unexpected kubectl call: %s\n' "$*" >&2
    exit 45
    ;;
esac
EOF
    chmod +x "${mock_bin}/kubectl" || return $?

    sed \
      -e "s|replicas_history_file=\"/rustfs-config/RUSTFS_REPLICAS_HISTORY\"|replicas_history_file=\"${history_file}\"|" \
      -e 's/namespace={{ .CLUSTER_NAMESPACE }}/namespace=test/' \
      -e 's/name={{ .RUSTFS_COMPONENT_NAME }}-rustfs-configuration/name=rustfs-rustfs-configuration/' \
      "${SHELLSPEC_CWD}/addons/rustfs/scripts/replicas-history-config.sh" \
      >"${case_dir}/replicas-history-config.sh" || return $?
    chmod +x "${case_dir}/replicas-history-config.sh" || return $?

    export PATH="${mock_bin}:${PATH}"
    export KUBECTL_CALL_LOG="${call_log}"
    export KUBECTL_GET_COUNT_FILE="${case_dir}/kubectl.get-count"
    printf '0\n' >"${KUBECTL_GET_COUNT_FILE}" || return $?
    export KUBECTL_RACE_PHASE_FILE="${case_dir}/kubectl.race-phase"
    printf '0\n' >"${KUBECTL_RACE_PHASE_FILE}" || return $?
    export RUSTFS_COMP_REPLICAS=8
  }

  cleanup_case() {
    rm -rf "${case_dir}"
  }

  run_case() {
    KUBECTL_GET_MODE="${1:-present}" \
      KUBECTL_READ_MODE="${2:-success}" \
      KUBECTL_CREATE_MODE="${3:-success}" \
      KUBECTL_PATCH_MODE="${4:-success}" \
      KUBECTL_RECHECK_MODE="${5:-}" \
      KUBECTL_READ_VALUE="${6-[4]}" \
      "${SHELLSPEC_SHELL}" "${case_dir}/replicas-history-config.sh"
  }

  BeforeEach 'setup_case'
  AfterEach 'cleanup_case'

  It "updates ConfigMap history and writes the confirmed value locally"
    When call run_case present success success success
    The status should be success
    The output should include "updated successfully"
    The contents of file "${history_file}" should eq "[4,8]"
    The contents of file "${call_log}" should include 'patch configmap rustfs-rustfs-configuration -n test --type strategic -p {"metadata":{"resourceVersion":"1"},"data":{"RUSTFS_REPLICAS_HISTORY":"[4,8]"}}'
  End

  It "creates a missing ConfigMap and writes the initial history snapshot"
    When call run_case absent success success success '' ''
    The status should be success
    The output should include "updated successfully"
    The contents of file "${history_file}" should eq "[8]"
  End

  It "replaces the local snapshot when an init container retries"
    run_case present success success success >/dev/null || return $?
    When call run_case present success success success
    The status should be success
    The output should include "updated successfully"
    The contents of file "${history_file}" should eq "[4,8]"
  End

  It "fails closed when ConfigMap data cannot be read"
    When call run_case present fail success success
    The status should be failure
    The stderr should include "Failed to read RUSTFS_REPLICAS_HISTORY"
    The path "${history_file}" should not be exist
  End

  It "fails closed when the ConfigMap snapshot has no resource version"
    When call run_case present malformed success success
    The status should be failure
    The stderr should include "Failed to parse RUSTFS_REPLICAS_HISTORY snapshot"
    The path "${history_file}" should not be exist
  End

  It "fails closed when a missing ConfigMap cannot be created"
    When call run_case absent success fail success
    The status should be failure
    The stderr should include "Failed to create ConfigMap"
    The path "${history_file}" should not be exist
  End

  It "fails closed when the ConfigMap patch is rejected"
    When call run_case present success success fail
    The status should be failure
    The stderr should include "Failed to update RUSTFS_REPLICAS_HISTORY"
    The path "${history_file}" should not be exist
  End

  It "fails closed when ConfigMap existence cannot be checked"
    When call run_case fail success success success
    The status should be failure
    The stderr should include "Failed to check ConfigMap"
    The path "${history_file}" should not be exist
  End

  It "fails closed when confirmed ConfigMap history cannot be written locally"
    rm -rf "${history_dir}"
    When call run_case present success success success
    The status should be failure
    The stderr should include "Failed to write RUSTFS_REPLICAS_HISTORY"
    The output should not include "written to the local file"
    The path "${history_file}" should not be exist
  End

  It "continues when another pod creates the missing ConfigMap concurrently"
    When call run_case absent success fail success present
    The status should be success
    The output should include "updated successfully"
    The contents of file "${history_file}" should eq "[4,8]"
  End

  It "preserves a higher concurrent replicas history update"
    When call run_case present success success race
    The status should be success
    The output should include "RUSTFS_REPLICAS_HISTORY=[4,12]"
    The contents of file "${history_file}" should eq "[4,12]"
    The contents of file "${call_log}" should include 'patch configmap rustfs-rustfs-configuration -n test --type strategic -p {"metadata":{"resourceVersion":"2"},"data":{"RUSTFS_REPLICAS_HISTORY":"[4,12]"}}'
  End

  It "fails closed when create fails and the ConfigMap remains absent"
    When call run_case absent success fail success absent
    The status should be failure
    The stderr should include "Failed to create ConfigMap"
    The path "${history_file}" should not be exist
  End

  It "fails closed when create fails and existence cannot be rechecked"
    When call run_case absent success fail success fail
    The status should be failure
    The stderr should include "Failed to create ConfigMap"
    The path "${history_file}" should not be exist
  End
End
