# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "RabbitMQ Backup/Restore contract"
  bpt_file="../templates/backuppolicytemplate.yaml"
  actionset_file="../templates/backupactionset.yaml"
  backup_script="../dataprotection/backup.sh"
  restore_script="../dataprotection/restore.sh"
  post_restore_script="../dataprotection/post-restore.sh"
  restore_example="../../../examples/rabbitmq/restore.yaml"
  readme="../../../examples/rabbitmq/README.md"

  It "binds a physical backup method to RabbitMQ ComponentDefinitions"
    When call grep -E "serviceKind: rabbitmq|strategy: All|name: physical|actionSetName: rabbitmq-physical-br" "${bpt_file}"
    The status should be success
    The stdout should include "serviceKind: rabbitmq"
    The stdout should include "strategy: All"
    The stdout should include "name: physical"
    The stdout should include "actionSetName: rabbitmq-physical-br"
  End

  It "targets the RabbitMQ data volume and maps the backup job image by serviceVersion"
    When call grep -E "name: data|mountPath: \\{\\{ \\.Values\\.dataMountPath \\}\\}|versionMapping|mappedValue:" "${bpt_file}"
    The status should be success
    The stdout should include "name: data"
    The stdout should include "mountPath: {{ .Values.dataMountPath }}"
    The stdout should include "versionMapping"
    The stdout should include "mappedValue:"
  End

  It "overrides RABBITMQ_NODENAME with DP_TARGET_POD_NAME for job pods"
    When call grep -F 'rabbit@$(DP_TARGET_POD_NAME).$(K8S_SERVICE_NAME).$(POD_NAMESPACE)' "${actionset_file}"
    The status should be success
    The stdout should include 'rabbit@$(DP_TARGET_POD_NAME).$(K8S_SERVICE_NAME).$(POD_NAMESPACE)'
  End

  It "wires backup, prepareData restore, and postReady account reconciliation scripts"
    When call grep -E "dataprotection/backup.sh|dataprotection/restore.sh|dataprotection/post-restore.sh|postReady:" "${actionset_file}"
    The status should be success
    The stdout should include "dataprotection/backup.sh"
    The stdout should include "dataprotection/restore.sh"
    The stdout should include "dataprotection/post-restore.sh"
    The stdout should include "postReady:"
  End

  It "uses a coordinated all-target stop and archive barrier for physical backup"
    When call grep -E "MARKER_BASE_PATH|write_marker ready|wait_for_markers ready|write_marker stopped|wait_for_markers stopped|write_marker archived|wait_for_markers archived|stop_app|start_app" "${backup_script}"
    The status should be success
    The stdout should include "MARKER_BASE_PATH"
    The stdout should include "write_marker ready"
    The stdout should include "wait_for_markers ready"
    The stdout should include "write_marker stopped"
    The stdout should include "wait_for_markers stopped"
    The stdout should include "write_marker archived"
    The stdout should include "wait_for_markers archived"
    The stdout should include "stop_app"
    The stdout should include "start_app"
  End

  It "waits for all targets to finish startup and discovery before any stop_app call"
    When call bash -c '
      set -Eeuo pipefail
      backup_script="$1"
      write_ready_line="$(grep -n "write_marker ready" "${backup_script}" | cut -d: -f1)"
      wait_ready_line="$(grep -n "wait_for_markers ready" "${backup_script}" | cut -d: -f1)"
      stop_call_line="$(grep -n '"'"'stop_node_app "${node}"'"'"' "${backup_script}" | cut -d: -f1)"
      test -n "${write_ready_line}"
      test -n "${wait_ready_line}"
      test -n "${stop_call_line}"
      test "${write_ready_line}" -lt "${wait_ready_line}"
      test "${wait_ready_line}" -lt "${stop_call_line}"
    ' _ "${backup_script}"
    The status should be success
  End

  It "writes per-pod archives and reports size for the current archive only"
    When call grep -E "ARCHIVE_NAME=.*TARGET_POD_NAME.*\\.tar\\.zst|datasafed push|datasafed stat.*ARCHIVE_NAME" "${backup_script}"
    The status should be success
    The stdout should include "ARCHIVE_NAME"
    The stdout should include "datasafed push"
    The stdout should include "datasafed stat"
  End

  It "makes backup fail closed and writes the dataprotection failure marker"
    When call grep -E "DP_BACKUP_INFO_FILE.*\\.exit|trap mark_failed EXIT" "${backup_script}"
    The status should be success
    The stdout should include "DP_BACKUP_INFO_FILE"
    The stdout should include "trap mark_failed EXIT"
  End

  It "refuses to restore over a non-empty data directory and pulls the mapped per-pod archive"
    When call grep -E "refusing to overwrite existing RabbitMQ data|lost\\+found|ARCHIVE_NAME=.*TARGET_POD_NAME.*\\.tar\\.zst|datasafed pull|chown -R rabbitmq:rabbitmq" "${restore_script}"
    The status should be success
    The stdout should include "refusing to overwrite existing RabbitMQ data"
    The stdout should include "lost+found"
    The stdout should include "ARCHIVE_NAME"
    The stdout should include "datasafed pull"
    The stdout should include "chown -R rabbitmq:rabbitmq"
  End

  It "allows a fresh PVC that only contains lost+found during restore"
    When call bash -c '
      set -Eeuo pipefail
      restore_script="$1"
      tmp_dir="$(mktemp -d)"
      trap "rm -rf \"${tmp_dir}\"" EXIT
      data_dir="${tmp_dir}/data"
      bin_dir="${tmp_dir}/bin"
      payload_dir="${tmp_dir}/payload"
      mkdir -p "${data_dir}/lost+found" "${bin_dir}" "${payload_dir}"
      printf "restored\n" > "${payload_dir}/restored.txt"
      tar -cf "${tmp_dir}/payload.tar" -C "${payload_dir}" .
      cat > "${bin_dir}/datasafed" <<'"'"'DATASAFED'"'"'
#!/bin/bash
set -e
case "$1" in
  list)
    printf "%s\n" "${DP_TARGET_POD_NAME}.tar.zst"
    ;;
  pull)
    cat "${FAKE_ARCHIVE_PATH}"
    ;;
  *)
    echo "unexpected datasafed command: $*" >&2
    exit 1
    ;;
esac
DATASAFED
      printf "#!/bin/bash\nexit 0\n" > "${bin_dir}/chown"
      chmod +x "${bin_dir}/datasafed"
      chmod +x "${bin_dir}/chown"
      PATH="${bin_dir}:${PATH}" \
        DATA_DIR="${data_dir}" \
        DP_TARGET_POD_NAME="rabbitmq-cluster-rabbitmq-0" \
        DP_TARGET_RELATIVE_PATH="ignored/extra/depth" \
        DP_BACKUP_BASE_PATH="/backup/base" \
        FAKE_ARCHIVE_PATH="${tmp_dir}/payload.tar" \
        bash "${restore_script}"
      test -f "${data_dir}/restored.txt"
      test -d "${data_dir}/lost+found"
      test ! -f "${data_dir}/.kb-data-protection"
    ' _ "${restore_script}"
    The status should be success
    The stdout should include "restore prepareData completed"
  End

  It "accepts the single-segment volume-populator target path as the archive stem"
    When call bash -c '
      set -Eeuo pipefail
      restore_script="$1"
      tmp_dir="$(mktemp -d)"
      trap "rm -rf \"${tmp_dir}\"" EXIT
      data_dir="${tmp_dir}/data"
      bin_dir="${tmp_dir}/bin"
      payload_dir="${tmp_dir}/payload"
      mkdir -p "${data_dir}" "${bin_dir}" "${payload_dir}"
      printf "restored-via-relative\n" > "${payload_dir}/restored.txt"
      tar -cf "${tmp_dir}/payload.tar" -C "${payload_dir}" .
      cat > "${bin_dir}/datasafed" <<'"'"'DATASAFED'"'"'
#!/bin/bash
set -e
case "$1" in
  list)
    test "${DATASAFED_BACKEND_BASE_PATH}" = "${EXPECTED_BACKUP_BASE_PATH}"
    printf "%s\n" "${EXPECTED_TARGET_POD_NAME}.tar.zst"
    ;;
  pull)
    cat "${FAKE_ARCHIVE_PATH}"
    ;;
  *)
    echo "unexpected datasafed command: $*" >&2
    exit 1
    ;;
esac
DATASAFED
      printf "#!/bin/bash\nexit 0\n" > "${bin_dir}/chown"
      chmod +x "${bin_dir}/datasafed"
      chmod +x "${bin_dir}/chown"
      unset DP_TARGET_POD_NAME || true
      PATH="${bin_dir}:${PATH}" \
        DATA_DIR="${data_dir}" \
        DP_TARGET_RELATIVE_PATH="rmq-br-5400-rabbitmq-2" \
        DP_BACKUP_BASE_PATH="/backup/base/rmq-br-5400-rabbitmq-2" \
        EXPECTED_BACKUP_BASE_PATH="/backup/base/rmq-br-5400-rabbitmq-2" \
        EXPECTED_TARGET_POD_NAME="rmq-br-5400-rabbitmq-2" \
        FAKE_ARCHIVE_PATH="${tmp_dir}/payload.tar" \
        bash "${restore_script}"
      test -f "${data_dir}/restored.txt"
      test ! -f "${data_dir}/.kb-data-protection"
    ' _ "${restore_script}"
    The status should be success
    The stdout should include "restore prepareData completed"
  End

  It "uses the final pod segment from a two-segment volume-populator target path"
    When call bash -c '
      set -Eeuo pipefail
      restore_script="$1"
      tmp_dir="$(mktemp -d)"
      trap "rm -rf \"${tmp_dir}\"" EXIT
      data_dir="${tmp_dir}/data"
      bin_dir="${tmp_dir}/bin"
      payload_dir="${tmp_dir}/payload"
      mkdir -p "${data_dir}" "${bin_dir}" "${payload_dir}"
      printf "restored-via-relative\n" > "${payload_dir}/restored.txt"
      tar -cf "${tmp_dir}/payload.tar" -C "${payload_dir}" .
      cat > "${bin_dir}/datasafed" <<'"'"'DATASAFED'"'"'
#!/bin/bash
set -e
case "$1" in
  list)
    test "${DATASAFED_BACKEND_BASE_PATH}" = "${EXPECTED_BACKUP_BASE_PATH}"
    printf "%s\n" "${EXPECTED_TARGET_POD_NAME}.tar.zst"
    ;;
  pull)
    cat "${FAKE_ARCHIVE_PATH}"
    ;;
  *)
    echo "unexpected datasafed command: $*" >&2
    exit 1
    ;;
esac
DATASAFED
      printf "#!/bin/bash\nexit 0\n" > "${bin_dir}/chown"
      chmod +x "${bin_dir}/datasafed" "${bin_dir}/chown"
      unset DP_TARGET_POD_NAME || true
      PATH="${bin_dir}:${PATH}" \
        DATA_DIR="${data_dir}" \
        DP_TARGET_RELATIVE_PATH="rabbitmq/rmq-br-5400-rabbitmq-2" \
        DP_BACKUP_BASE_PATH="/backup/base/rabbitmq/rmq-br-5400-rabbitmq-2" \
        EXPECTED_BACKUP_BASE_PATH="/backup/base/rabbitmq/rmq-br-5400-rabbitmq-2" \
        EXPECTED_TARGET_POD_NAME="rmq-br-5400-rabbitmq-2" \
        FAKE_ARCHIVE_PATH="${tmp_dir}/payload.tar" \
        bash "${restore_script}"
      test -f "${data_dir}/restored.txt"
      test ! -f "${data_dir}/.kb-data-protection"
    ' _ "${restore_script}"
    The status should be success
    The stdout should include "restore prepareData completed"
  End

  It "fails closed when the target relative path has an empty final segment"
    When call bash -c '
      set -Eeuo pipefail
      restore_script="$1"
      unset DP_TARGET_POD_NAME || true
      DATA_DIR="$(mktemp -d)" \
        DP_TARGET_RELATIVE_PATH="rabbitmq/" \
        DP_BACKUP_BASE_PATH="/backup/base/rabbitmq" \
        bash "${restore_script}"
    ' _ "${restore_script}"
    The status should be failure
    The stderr should include "must be one pod segment or <target-name>/<target-pod-name>"
  End

  It "fails closed when the target relative path has extra depth"
    When call bash -c '
      set -Eeuo pipefail
      restore_script="$1"
      unset DP_TARGET_POD_NAME || true
      DATA_DIR="$(mktemp -d)" \
        DP_TARGET_RELATIVE_PATH="repo/rabbitmq/rmq-br-5400-rabbitmq-2" \
        DP_BACKUP_BASE_PATH="/backup/base/repo/rabbitmq/rmq-br-5400-rabbitmq-2" \
        bash "${restore_script}"
    ' _ "${restore_script}"
    The status should be failure
    The stderr should include "must be one pod segment or <target-name>/<target-pod-name>"
  End

  It "fails closed when neither DP_TARGET_POD_NAME nor DP_TARGET_RELATIVE_PATH is set"
    When call bash -c '
      set -Eeuo pipefail
      restore_script="$1"
      unset DP_TARGET_POD_NAME DP_TARGET_RELATIVE_PATH || true
      DATA_DIR="$(mktemp -d)" DP_BACKUP_BASE_PATH="/backup/base" bash "${restore_script}"
    ' _ "${restore_script}"
    The status should be failure
    The stderr should include "DP_TARGET_POD_NAME or DP_TARGET_RELATIVE_PATH is required"
  End

  It "reconciles the restored system account idempotently after RabbitMQ is ready"
    When call grep -E "await_startup|ensure_system_user|change_password|add_user|set_user_tags|set_permissions" "${post_restore_script}"
    The status should be success
    The stdout should include "await_startup"
    The stdout should include "ensure_system_user"
    The stdout should include "change_password"
    The stdout should include "add_user"
    The stdout should include "set_user_tags"
    The stdout should include "set_permissions"
  End

  It "documents restore as same-identity physical recovery with target mapping guidance"
    When call grep -E "name: rabbitmq-cluster|source-target-name: rabbitmq|volume-restore-policy: Parallel|source-target-pod-name|same identity mapping|per-pod artifact" "${restore_example}" "${readme}"
    The status should be success
    The stdout should include "name: rabbitmq-cluster"
    The stdout should include "source-target-name: rabbitmq"
    The stdout should include "volume-restore-policy: Parallel"
    The stdout should include "source-target-pod-name"
    The stdout should include "per-pod artifact"
  End
End
