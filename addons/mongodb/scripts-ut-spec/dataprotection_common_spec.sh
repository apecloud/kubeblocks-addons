# shellcheck shell=bash

Describe "MongoDB dataprotection common scripts"
  setup_config_env() {
    export DATASAFED_CONFIG_FILE="./datasafed-test.conf"
    export DP_BACKUP_BASE_PATH="/mongodb-test/backup-name"
    export PBM_BACKUP_DIR_NAME="pbm"
    unset S3_FORCE_PATH_STYLE
  }
  Before "setup_config_env"

  cleanup_config_env() {
    rm -f "$DATASAFED_CONFIG_FILE"
    unset DATASAFED_CONFIG_FILE
    unset DP_BACKUP_BASE_PATH
    unset PBM_BACKUP_DIR_NAME
    unset S3_FORCE_PATH_STYLE
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
End
