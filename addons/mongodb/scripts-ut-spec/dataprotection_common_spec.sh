# shellcheck shell=bash

Describe "MongoDB dataprotection storage config"
  setup_config_env() {
    export DATASAFED_CONFIG_FILE="./datasafed-test-${$}.conf"
    export PBM_CONFIG_FILE="./pbm-config-${$}.yaml"
    export DP_BACKUP_BASE_PATH="/mongodb-test/backup-name"
    export PBM_BACKUP_DIR_NAME="pbm"
    unset S3_FORCE_PATH_STYLE
  }
  Before "setup_config_env"

  cleanup_config_env() {
    rm -f "$DATASAFED_CONFIG_FILE"
    rm -f "$PBM_CONFIG_FILE"
    unset DATASAFED_CONFIG_FILE
    unset PBM_CONFIG_FILE
    unset DP_BACKUP_BASE_PATH
    unset PBM_BACKUP_DIR_NAME
    unset S3_FORCE_PATH_STYLE
    unset PBM_MONGODB_URI
    unset S3_REGION
    unset S3_ENDPOINT
    unset S3_BUCKET
    unset S3_PREFIX
    unset S3_ACCESS_KEY
    unset S3_SECRET_KEY
  }
  After "cleanup_config_env"

  run_set_backup_config_env() {
    source ../dataprotection/common-scripts.sh
    set_backup_config_env >/dev/null
    echo "force_path_style=${S3_FORCE_PATH_STYLE:-}"
  }

  write_datasafed_config() {
    cat > "$DATASAFED_CONFIG_FILE" <<EOF
type = s3
provider = $1
access_key_id = access-key
secret_access_key = secret-key
region = us-east-1
endpoint = http://minio.example.com
root = mongodb-bucket
$2
EOF
  }

  It "uses explicit force_path_style=false from datasafed config"
    write_datasafed_config "Minio" "force_path_style = false"

    When call run_set_backup_config_env

    The output should include "force_path_style=false"
    The status should be success
  End

  It "uses explicit force_path_style=true from datasafed config"
    write_datasafed_config "Alibaba" "force_path_style = true"

    When call run_set_backup_config_env

    The output should include "force_path_style=true"
    The status should be success
  End

  It "keeps Minio provider fallback when force_path_style is absent"
    write_datasafed_config "Minio" ""

    When call run_set_backup_config_env

    The output should include "force_path_style=true"
    The status should be success
  End

  run_write_pbm_storage_config() {
    source ../dataprotection/common-scripts.sh
    export S3_REGION="us-east-1"
    export S3_ENDPOINT="http://minio.example.com"
    export S3_BUCKET="mongodb-bucket"
    export S3_PREFIX="mongodb-test/pbm"
    export S3_ACCESS_KEY="access-key"
    export S3_SECRET_KEY="secret-key"
    export S3_FORCE_PATH_STYLE="true"

    write_pbm_storage_config_file "$PBM_CONFIG_FILE"
    cat "$PBM_CONFIG_FILE"
  }

  It "writes forcePathStyle to the PBM storage config file"
    When call run_write_pbm_storage_config

    The output should include "forcePathStyle: true"
    The status should be success
  End
End

Describe "MongoDB dataprotection common script"
  Include ../dataprotection/common-scripts.sh

  setup_polling() {
    POLL_STATE_FILE="$(mktemp)"
    echo 0 > "$POLL_STATE_FILE"
    export SYNCER_PBM_WAIT_INTERVAL_SECONDS=0
    export SYNCER_RESTORE_WAIT_INTERVAL_SECONDS=0
  }
  BeforeEach 'setup_polling'

  cleanup_polling() {
    rm -f "$POLL_STATE_FILE"
  }
  AfterEach 'cleanup_polling'

  sleep() { :; }

  syncerctl_cmd() {
    local count
    count=$(cat "$POLL_STATE_FILE")
    count=$((count + 1))
    echo "$count" > "$POLL_STATE_FILE"

    if [ "$1 $2" = "backup status" ]; then
      if [ "$count" -lt 3 ]; then
        echo '{"found":true,"status":"running"}'
      else
        echo '{"found":true,"status":"done"}'
      fi
      return
    fi

    if [ "$count" -lt 3 ]; then
      echo '{"status":"running","phase":"in-restore"}'
    else
      echo '{"status":"done","phase":"done"}'
    fi
  }

  It "waits for backup completion without a retry limit"
    When call wait_for_syncer_backup_completion "backup-1"
    The status should be success
    The output should include "Backup backup-1 status: found=true status=done"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End

  It "waits for restore completion without a retry limit"
    When call wait_for_syncer_restore_completion "request-1"
    The status should be success
    The output should include "Restore request request-1 phase=done"
    The contents of file "$POLL_STATE_FILE" should equal 3
  End
End
