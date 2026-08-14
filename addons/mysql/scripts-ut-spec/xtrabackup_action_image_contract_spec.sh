# shellcheck shell=sh

Describe "MySQL xtrabackup action image contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  render_template() {
    template=$1
    shift
    helm template test "$(chart_path)" --show-only "templates/${template}" "$@"
  }

  mapped_method_env() {
    template=$1
    method=$2
    env_name=$3
    service_version=$4
    shift 4

    render_template "$template" "$@" | awk \
      -v method="$method" \
      -v env_name="$env_name" \
      -v service_version="$service_version" '
        /^  - name: / {
          current_method = $3
          in_method = (current_method == method)
          in_image_mapping = 0
          candidate = 0
        }
        in_method && $1 == "-" && $2 == "name:" && $3 == env_name {
          in_image_mapping = 1
          next
        }
        in_image_mapping && /- serviceVersions:$/ {
          candidate = 0
          next
        }
        in_image_mapping && $1 == "-" {
          series = $2
          gsub(/"/, "", series)
          candidate = (index(service_version, series) == 1)
          next
        }
        in_image_mapping && candidate && $1 == "mappedValue:" {
          image = $2
          gsub(/"/, "", image)
          print image
          found = 1
          exit
        }
        END { if (!found) exit 1 }
      '
  }

  mapped_xtrabackup_image() {
    template=$1
    method=$2
    service_version=$3
    shift 3
    mapped_method_env "$template" "$method" XTRABACKUP_IMAGE "$service_version" "$@"
  }

  method_action_set_name() {
    template=$1
    method=$2
    shift 2

    render_template "$template" "$@" | awk \
      -v method="$method" '
        /^  - name: / { in_method = ($3 == method) }
        in_method && $1 == "actionSetName:" { print $2; found = 1; exit }
        END { if (!found) exit 1 }
      '
  }

  action_set_name() {
    template=$1
    shift

    render_template "$template" "$@" | awk '
      /^metadata:$/ { in_metadata = 1; next }
      in_metadata && $1 == "name:" { print $2; found = 1; exit }
      END { if (!found) exit 1 }
    '
  }

  action_restore_image() {
    template=$1
    shift

    render_template "$template" "$@" | awk '
      /^  restore:$/ { in_restore = 1; next }
      in_restore && /^      image: / {
        sub(/^      image: /, "")
        print
        found = 1
        exit
      }
      END { if (!found) exit 1 }
    '
  }

  resolve_action_image() {
    policy_template=$1
    method=$2
    action_template=$3
    service_version=$4
    shift 4

    action_image=$(render_template "$action_template" "$@" |
      awk '/^      image: / { sub(/^      image: /, ""); print; exit }') || return 1
    [ "$(method_action_set_name "$policy_template" "$method" "$@")" = \
      "$(action_set_name "$action_template" "$@")" ] || return 1
    [ "$action_image" = '$(XTRABACKUP_IMAGE)' ] || return 1
    mapped_xtrabackup_image "$policy_template" "$method" "$service_version" "$@"
  }

  resolve_legacy_restore_image() {
    action_template=$1
    image_tag=$2
    shift 2

    image=$(action_restore_image "$action_template" "$@") || return 1
    case "$image" in
      *'$(XTRABACKUP_IMAGE)'*) return 1 ;;
      *'$(IMAGE_TAG)'*) printf "%s" "${image%'$(IMAGE_TAG)'}${image_tag}" ;;
      *) return 1 ;;
    esac
  }

  resolve_restore_image_from_legacy_backup_status() {
    action_template=$1
    persisted_action_set=$2
    persisted_image_tag=$3
    shift 3

    backup_status_env=$(printf '%s\n' \
      'env:' \
      '  - name: IMAGE_TAG' \
      "    value: \"${persisted_image_tag}\"") || return 1
    ! printf '%s\n' "$backup_status_env" | grep -q XTRABACKUP_IMAGE || return 1
    [ "$(action_set_name "$action_template" "$@")" = "$persisted_action_set" ] || return 1
    image_tag=$(printf '%s\n' "$backup_status_env" | awk '
      $1 == "-" && $2 == "name:" { is_image_tag = ($3 == "IMAGE_TAG"); next }
      is_image_tag && $1 == "value:" {
        value = $2
        gsub(/"/, "", value)
        print value
        found = 1
        exit
      }
      END { if (!found) exit 1 }
    ') || return 1
    resolve_legacy_restore_image "$action_template" "$image_tag" "$@"
  }

  resolve_lock_flag_from_script() {
    script=$1
    image_tag=$2
    block=$(awk '/^lock_per_table_ddl=""$/, /^fi$/' "$(chart_path)/dataprotection/${script}") || return 1
    [ -n "$block" ] || return 1
    IMAGE_TAG="$image_tag" bash -c "${block}
printf '%s' \"\${lock_per_table_ddl}\""
  }

  resolve_method_lock_flag() {
    policy_template=$1
    method=$2
    script=$3
    service_version=$4
    shift 4

    image_tag=$(mapped_method_env "$policy_template" "$method" IMAGE_TAG "$service_version" "$@") || return 1
    resolve_lock_flag_from_script "$script" "$image_tag"
  }

  verify_nonlegacy_tool_versions() {
    [ "$(mapped_method_env backuppolicytemplate.yaml xtrabackup IMAGE_TAG 8.0.46)" = "8.0.35" ] || return 1
    [ "$(mapped_method_env backuppolicytemplate-orc.yaml xtrabackup-inc IMAGE_TAG 8.4.10)" = "8.4.0" ] || return 1
    [ -z "$(resolve_method_lock_flag backuppolicytemplate.yaml xtrabackup backup.sh 8.0.46)" ] || return 1
    [ -z "$(resolve_method_lock_flag backuppolicytemplate-orc.yaml xtrabackup-inc xtrabackup-incremental-backup.sh 8.4.10)" ]
  }

  verify_all_tool_version_mappings() {
    for template in backuppolicytemplate.yaml backuppolicytemplate-orc.yaml; do
      for method in xtrabackup xtrabackup-inc; do
        [ "$(mapped_method_env "$template" "$method" IMAGE_TAG 5.7.44)" = "2.4" ] || return 1
        [ "$(mapped_method_env "$template" "$method" IMAGE_TAG 8.0.46)" = "8.0.35" ] || return 1
        [ "$(mapped_method_env "$template" "$method" IMAGE_TAG 8.4.10)" = "8.4.0" ] || return 1
      done
    done
  }

  verify_all_action_image_mappings() {
    for template in backuppolicytemplate.yaml backuppolicytemplate-orc.yaml; do
      for method in xtrabackup xtrabackup-inc; do
        for service_version in 5.7.44 8.0.46 8.4.10; do
          case "$service_version" in
            5.7.44) expected="docker.io/apecloud/percona-xtrabackup:2.4@sha256:29ab5ecc6f1902b7e8713d5e9d108eeec7d484e1302b63bbcdaad1bc3494eabc" ;;
            8.0.46) expected="docker.io/apecloud/percona-xtrabackup:8.0@sha256:72ef9231ecc7dc1e323e0e7a45d2a93ff2b6fbdb685d6e28570dea9a26f15d6a" ;;
            8.4.10) expected="docker.io/apecloud/percona-xtrabackup:8.4@sha256:22bfd0eeb3984c75760127316c276c5ccf059ea28a04e7b7ea3f9c60fc2163b6" ;;
          esac
          actual=$(mapped_xtrabackup_image "$template" "$method" "$service_version") || return 1
          [ "$actual" = "$expected" ] || return 1
        done
      done
    done
  }

  reject_minimal_images_for_v2_methods() {
    for template in backuppolicytemplate.yaml backuppolicytemplate-orc.yaml; do
      for method in xtrabackup xtrabackup-inc; do
        for service_version in 5.7.44 8.0.46 8.4.10; do
          image=$(mapped_xtrabackup_image "$template" "$method" "$service_version") || return 1
          case "$image" in
            *xtrabackup-minimal*) return 1 ;;
          esac
        done
      done
    done
  }

  reject_empty_tool_versions() {
    ! resolve_lock_flag_from_script backup.sh "" 2>/dev/null || return 1
    ! resolve_lock_flag_from_script xtrabackup-incremental-backup.sh "" 2>/dev/null
  }

  verify_v2_action_shells() {
    output=$(render_template actionset-xtrabackup-v2.yaml) || return 1
    output="${output}
$(render_template actionset-xtrabackup-inc-v2.yaml)" || return 1
    [ "$(printf '%s\n' "$output" | grep -c '^      - bash$')" -eq 4 ]
  }

  verify_v2_restore_image_contracts() {
    for action_template in actionset-xtrabackup-v2.yaml actionset-xtrabackup-inc-v2.yaml; do
      [ "$(action_restore_image "$action_template")" = '$(XTRABACKUP_IMAGE)' ] || return 1
    done
    verify_all_action_image_mappings
  }

  verify_transient_dir_cleanup() {
    awk '
      /TMP_DIR=|BASE_DIR=|INCS_DIR=/ {
        var = $0
        sub(/=.*/, "", var)
        cleaned[var] = 0
      }
      /rm -rf \$\{(TMP_DIR|BASE_DIR|INCS_DIR)\}/ {
        line = $0
        sub(/^.*\$\{/, "", line)
        sub(/\}.*/, "", line)
        cleaned[line] = 1
      }
      /mkdir -p \$\{(TMP_DIR|BASE_DIR|INCS_DIR)\}/ {
        line = $0
        sub(/^.*\$\{/, "", line)
        sub(/\}.*/, "", line)
        if (!cleaned[line]) exit 1
      }
    ' \
      "$(chart_path)/dataprotection/backup.sh" \
      "$(chart_path)/dataprotection/restore.sh" \
      "$(chart_path)/dataprotection/xtrabackup-incremental-backup.sh" \
      "$(chart_path)/dataprotection/xtrabackup-incremental-restore.sh"
  }

  verify_stale_progress_state_cleanup() {
    for script in backup.sh xtrabackup-incremental-backup.sh; do
      awk '
        /rm -f "\$\{DP_BACKUP_INFO_FILE\}" "\$\{DP_BACKUP_INFO_FILE\}\.exit" "\$\{DP_BACKUP_INFO_FILE\}\.tmp"/ { cleaned = 1 }
        /xtrabackup --backup/ { exit !cleaned }
        END { if (!cleaned) exit 1 }
      ' "$(chart_path)/dataprotection/${script}" || return 1
    done
  }

  verify_backup_progress_is_terminal() {
    awk -v required=1 '
      /xtrabackup --backup/ { backup = 1 }
      backup && /rm -rf \$\{TMP_DIR\}/ { cleanups++ }
      /mv "\$\{DP_BACKUP_INFO_FILE\}\.tmp" "\$\{DP_BACKUP_INFO_FILE\}"/ {
        if (cleanups < required) exit 1
        progress = 1
      }
      END { if (!progress) exit 1 }
    ' "$(chart_path)/dataprotection/backup.sh" || return 1

    awk -v required=2 '
      /xtrabackup --backup/ { backup = 1 }
      backup && /rm -rf \$\{(PARENT_DIR|TMP_DIR)\}/ { cleanups++ }
      /mv "\$\{DP_BACKUP_INFO_FILE\}\.tmp" "\$\{DP_BACKUP_INFO_FILE\}"/ {
        if (cleanups < required) exit 1
        progress = 1
      }
      END { if (!progress) exit 1 }
    ' "$(chart_path)/dataprotection/xtrabackup-incremental-backup.sh"
  }

  verify_backup_progress_is_atomic() {
    for script in backup.sh xtrabackup-incremental-backup.sh; do
      awk '
        />"\$\{DP_BACKUP_INFO_FILE\}"/ { exit 1 }
        />"\$\{DP_BACKUP_INFO_FILE\}\.tmp"/ { staged = 1 }
        /mv "\$\{DP_BACKUP_INFO_FILE\}\.tmp" "\$\{DP_BACKUP_INFO_FILE\}"/ {
          if (!staged) exit 1
          published = 1
        }
        END { if (!staged || !published) exit 1 }
      ' "$(chart_path)/dataprotection/${script}" || return 1
    done
  }

  verify_failed_progress_publish_cleans_temp() {
    for script in backup.sh xtrabackup-incremental-backup.sh; do
      awk '
        /function handle_exit/ { in_handler = 1 }
        in_handler && /rm -f "\$\{DP_BACKUP_INFO_FILE\}\.tmp"/ { temp_cleaned = 1 }
        in_handler && /touch "\$\{DP_BACKUP_INFO_FILE\}\.exit"/ {
          if (!temp_cleaned) exit 1
          failure_marker = 1
        }
        in_handler && /^}/ { in_handler = 0 }
        END { if (!temp_cleaned || !failure_marker) exit 1 }
      ' "$(chart_path)/dataprotection/${script}" || return 1
    done
  }

  verify_backup_failure_preserves_exit_code() {
    for script in backup.sh xtrabackup-incremental-backup.sh; do
      awk '
        /function handle_exit/ { in_handler = 1 }
        in_handler && /exit 1/ { exit 1 }
        in_handler && /exit "\$\{exit_code\}"/ { preserved = 1 }
        in_handler && /^}/ { in_handler = 0 }
        END { if (!preserved) exit 1 }
      ' "$(chart_path)/dataprotection/${script}" || return 1
    done
  }

  verify_restore_markers_are_terminal() {
    for script in restore.sh xtrabackup-incremental-restore.sh; do
      awk '
        /rm -f .*\.xtrabackup_restore|rm -f .*\.restore_new_cluster/ { exit 1 }
        /chmod -R 0777/ { permissions_ready = 1 }
        /touch .*\.xtrabackup_restore/ { if (!permissions_ready) exit 1; restored = 1 }
        /touch .*\.restore_new_cluster/ { if (!restored) exit 1; new_cluster = 1 }
        END { if (!permissions_ready || !restored || !new_cluster) exit 1 }
      ' "$(chart_path)/dataprotection/${script}" || return 1
    done
  }

  verify_completed_restore_replay_preserves_markers() {
    for script in restore.sh xtrabackup-incremental-restore.sh; do
      root=$(mktemp -d "${TMPDIR:-/tmp}/mysql-restore-replay.XXXXXX") || return 1
      mkdir -p "${root}/data"
      touch "${root}/data/.xtrabackup_restore" "${root}/data/.restore_new_cluster"
      printf "valid-restored-data\n" >"${root}/data/replay-sentinel"

      (
        datasafed() {
          if [ "$1" = "list" ]; then
            printf "%s\n" "$2"
          fi
        }
        xbstream() { return 0; }
        xtrabackup() {
          for arg in "$@"; do
            if [ "${arg}" = "--move-back" ]; then
              return 42
            fi
          done
          return 0
        }
        export -f datasafed xbstream xtrabackup
        export MYSQL_DIR="${root}"
        export DATA_DIR="${root}/data"
        export DP_DATASAFED_BIN_PATH="/bin"
        export DP_BACKUP_BASE_PATH="/repo"
        export DP_BACKUP_NAME="current"
        export DP_BASE_BACKUP_NAME="base"
        export DP_BACKUP_ROOT_PATH="/root"
        export DP_TARGET_RELATIVE_PATH="data"
        export DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES=""
        export BACKUP_FOR_STANDBY="false"
        bash "$(chart_path)/dataprotection/${script}" >/dev/null 2>&1
      )
      status=$?

      [ "${status}" -eq 42 ] \
        && [ -f "${root}/data/.xtrabackup_restore" ] \
        && [ -f "${root}/data/.restore_new_cluster" ] \
        && [ "$(cat "${root}/data/replay-sentinel")" = "valid-restored-data" ] || {
          rm -rf "${root}"
          return 1
        }
      rm -rf "${root}"
    done
  }

  It "resolves the exact MySQL 5.7 full-backup Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup-v2.yaml 5.7.44
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:2.4@sha256:29ab5ecc6f1902b7e8713d5e9d108eeec7d484e1302b63bbcdaad1bc3494eabc"
  End

  It "cleans every transient backup directory before reuse"
    When call verify_transient_dir_cleanup
    The status should be success
  End

  It "clears stale backup progress and failure state before retrying"
    When call verify_stale_progress_state_cleanup
    The status should be success
  End


  It "publishes backup success progress only after final cleanup"
    When call verify_backup_progress_is_terminal
    The status should be success
  End

  It "publishes backup success progress atomically"
    When call verify_backup_progress_is_atomic
    The status should be success
  End

  It "removes staged progress before publishing backup failure"
    When call verify_failed_progress_publish_cleans_temp
    The status should be success
  End

  It "preserves the original backup failure exit code"
    When call verify_backup_failure_preserves_exit_code
    The status should be success
  End


  It "preserves durable restore markers and publishes them only after finalization"
    When call verify_restore_markers_are_terminal
    The status should be success
  End


  It "preserves completed restore data and markers when prepareData is replayed"
    When call verify_completed_restore_replay_preserves_markers
    The status should be success
  End

  It "resolves the exact MySQL 8.0 full-backup Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup-v2.yaml 8.0.46
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:8.0@sha256:72ef9231ecc7dc1e323e0e7a45d2a93ff2b6fbdb685d6e28570dea9a26f15d6a"
  End

  It "resolves the exact MySQL 8.4 full-backup Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup-v2.yaml 8.4.10
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:8.4@sha256:22bfd0eeb3984c75760127316c276c5ccf059ea28a04e7b7ea3f9c60fc2163b6"
  End

  It "uses the exact MySQL 8.0 image for incremental backup Jobs"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup-inc actionset-xtrabackup-inc-v2.yaml 8.0.46
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:8.0@sha256:72ef9231ecc7dc1e323e0e7a45d2a93ff2b6fbdb685d6e28570dea9a26f15d6a"
  End

  It "uses the exact MySQL 8.4 image for ORC full-backup Jobs"
    When call resolve_action_image backuppolicytemplate-orc.yaml xtrabackup actionset-xtrabackup-v2.yaml 8.4.10
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:8.4@sha256:22bfd0eeb3984c75760127316c276c5ccf059ea28a04e7b7ea3f9c60fc2163b6"
  End

  It "uses the exact MySQL 5.7 image for ORC incremental backup Jobs"
    When call resolve_action_image backuppolicytemplate-orc.yaml xtrabackup-inc actionset-xtrabackup-inc-v2.yaml 5.7.44
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:2.4@sha256:29ab5ecc6f1902b7e8713d5e9d108eeec7d484e1302b63bbcdaad1bc3494eabc"
  End

  It "preserves the bash-capable image override in the final MySQL 8.0 Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup-v2.yaml 8.0.46 \
      --set image.xtraBackup.registry=registry.example.com \
      --set image.xtraBackup.repository=team/xtrabackup
    The status should be success
    The output should equal "registry.example.com/team/xtrabackup:8.0@sha256:72ef9231ecc7dc1e323e0e7a45d2a93ff2b6fbdb685d6e28570dea9a26f15d6a"
  End

  It "fails closed when the immutable MySQL 8.0 image digest is empty"
    When call render_template backuppolicytemplate.yaml --set-string image.xtraBackup.digest80=
    The status should be failure
    The error should include "image.xtraBackup.digest80 is required"
  End

  It "fails closed when an immutable xtrabackup image digest is malformed"
    When call render_template backuppolicytemplate.yaml \
      --set-string image.xtraBackup.digest80=not-a-digest
    The status should be failure
    The error should include "image.xtraBackup.digest80 must be sha256:<64 lowercase hex>"
  End

  It "fails closed when the immutable MySQL 5.7 image digest is empty"
    When call render_template backuppolicytemplate.yaml --set-string image.xtraBackup.digest57=
    The status should be failure
    The error should include "image.xtraBackup.digest57 is required"
  End

  It "fails closed when the immutable MySQL 8.4 image digest is malformed"
    When call render_template backuppolicytemplate.yaml \
      --set-string image.xtraBackup.digest84=sha256:1234
    The status should be failure
    The error should include "image.xtraBackup.digest84 must be sha256:<64 lowercase hex>"
  End

  It "preserves the legacy-image override in the final MySQL 5.7 Job image"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup-v2.yaml 5.7.44 \
      --set image.xtraBackup.registry=registry.example.com \
      --set image.xtraBackup.repository=team/xtrabackup
    The status should be success
    The output should equal "registry.example.com/team/xtrabackup:2.4@sha256:29ab5ecc6f1902b7e8713d5e9d108eeec7d484e1302b63bbcdaad1bc3494eabc"
  End

  It "fails closed when the service version has no xtrabackup image mapping"
    When call resolve_action_image backuppolicytemplate.yaml xtrabackup actionset-xtrabackup-v2.yaml 9.0.0
    The status should be failure
    The output should be blank
  End

  It "leaves no ActionSet-level fallback image for an unmapped service version"
    When call sh -c '
      set -e
      output=$(helm template test "$1" \
        --show-only templates/actionset-xtrabackup-v2.yaml \
        --show-only templates/actionset-xtrabackup-inc-v2.yaml)
      [ "$(printf "%s\n" "$output" | grep -c "image: \$(XTRABACKUP_IMAGE)")" -eq 4 ]
      ! printf "%s\n" "$output" | grep -q "name: IMAGE_TAG"
      ! printf "%s\n" "$output" | grep -q "name: XTRABACKUP_IMAGE"
    ' sh "$(chart_path)"
    The status should be success
  End

  It "keeps every v2 backup and restore script on bash"
    When call verify_v2_action_shells
    The status should be success
  End

  It "binds every v2 restore action to the immutable image persisted by its policy mapping"
    When call verify_v2_restore_image_contracts
    The status should be success
  End


  It "keeps an old full Backup restorable after the chart upgrade"
    When call resolve_restore_image_from_legacy_backup_status \
      actionset-xtrabackup.yaml mysql-xtrabackup-br 8.0
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:8.0"
  End

  It "keeps an old incremental Backup restorable after the chart upgrade"
    When call resolve_restore_image_from_legacy_backup_status \
      actionset-xtrabackup-inc.yaml mysql-xtrabackup-inc-br 2.4
    The status should be success
    The output should equal "docker.io/apecloud/percona-xtrabackup:2.4"
  End

  It "maps the standard MySQL 5.7 full-backup method into the 2.4 script branch"
    When call resolve_method_lock_flag backuppolicytemplate.yaml xtrabackup backup.sh 5.7.44
    The status should be success
    The output should equal "--lock-ddl-per-table"
  End

  It "maps the ORC MySQL 5.7 incremental method into the 2.4 script branch"
    When call resolve_method_lock_flag backuppolicytemplate-orc.yaml xtrabackup-inc xtrabackup-incremental-backup.sh 5.7.44
    The status should be success
    The output should equal "--lock-ddl-per-table"
  End

  It "maps exact non-legacy tool versions without entering the 2.4 script branch"
    When call verify_nonlegacy_tool_versions
    The status should be success
  End

  It "maps exact tool versions for full and incremental methods in standard and ORC policies"
    When call verify_all_tool_version_mappings
    The status should be success
  End

  It "maps bash-capable images for all 12 policy, method, and MySQL version cells"
    When call verify_all_action_image_mappings
    The status should be success
  End

  It "keeps xtrabackup-minimal out of every v2 backup method"
    When call reject_minimal_images_for_v2_methods
    The status should be success
  End

  It "fails closed when the service version has no tool-version mapping"
    When call resolve_method_lock_flag backuppolicytemplate.yaml xtrabackup backup.sh 9.0.0
    The status should be failure
    The output should be blank
  End

  It "makes both backup scripts reject an empty tool version"
    When call reject_empty_tool_versions
    The status should be success
  End
End
