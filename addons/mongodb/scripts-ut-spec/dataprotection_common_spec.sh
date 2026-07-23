# shellcheck shell=bash

Describe "MongoDB dataprotection common scripts"
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
    echo "region=${S3_REGION:-}"
    echo "endpoint=${S3_ENDPOINT:-}"
  }

  write_datasafed_config() {
    cat > "$DATASAFED_CONFIG_FILE" <<EOF
type = s3
provider = $1
access_key_id = access-key
secret_access_key = secret-key
region = ${4:-initial-region}
endpoint = ${3:-http://minio.example.com}
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
    write_datasafed_config "Alibaba" "force_path_style = true" \
      "https://oss-cn-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "force_path_style=true"
    The output should include "region=cn-hangzhou"
    The output should include "endpoint=https://oss-cn-hangzhou.aliyuncs.com"
    The status should be success
  End

  It "extracts the region from an Alibaba HTTP endpoint"
    write_datasafed_config "Alibaba" "" \
      "http://oss-cn-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou"
    The output should include "endpoint=http://oss-cn-hangzhou.aliyuncs.com"
    The status should be success
  End

  It "normalizes an Alibaba endpoint without a scheme to HTTPS"
    write_datasafed_config "Alibaba" "" \
      "oss-cn-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou"
    The output should include "endpoint=https://oss-cn-hangzhou.aliyuncs.com"
    The status should be success
  End

  It "extracts an official digit-bearing Alibaba region"
    write_datasafed_config "Alibaba" "" \
      "https://oss-ap-southeast-1.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=ap-southeast-1"
    The status should be success
  End

  It "accepts a one-character Alibaba region label"
    write_datasafed_config "Alibaba" "" \
      "https://oss-a.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=a"
    The status should be success
  End

  It "accepts a 63-character Alibaba region label"
    write_datasafed_config "Alibaba" "" \
      "https://oss-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    The status should be success
  End

  It "extracts the region from an Alibaba internal endpoint"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hangzhou-internal.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou"
    The status should be success
  End

  It "extracts the region from an Alibaba HTTP internal endpoint"
    write_datasafed_config "Alibaba" "" \
      "http://oss-cn-hangzhou-internal.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou"
    The status should be success
  End

  It "extracts the region from an Alibaba dual-stack endpoint"
    write_datasafed_config "Alibaba" "" \
      "https://cn-hangzhou.oss.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou"
    The status should be success
  End

  It "extracts the region from an Alibaba HTTP dual-stack endpoint"
    write_datasafed_config "Alibaba" "" \
      "http://cn-hangzhou.oss.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou"
    The status should be success
  End

  It "keeps the configured region for an Alibaba acceleration endpoint"
    write_datasafed_config "Alibaba" "" \
      "https://oss-accelerate.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba HTTP acceleration endpoint"
    write_datasafed_config "Alibaba" "" \
      "http://oss-accelerate.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba overseas acceleration endpoint"
    write_datasafed_config "Alibaba" "" \
      "https://oss-accelerate-overseas.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba HTTP overseas acceleration endpoint"
    write_datasafed_config "Alibaba" "" \
      "http://oss-accelerate-overseas.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "preserves the canonical region for an Alibaba Finance Cloud public alias"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hzfinance.aliyuncs.com" \
      "cn-hangzhou-finance"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou-finance"
    The output should include "endpoint=https://oss-cn-hzfinance.aliyuncs.com"
    The status should be success
  End

  It "preserves the canonical region for an Alibaba Finance Cloud internal alias"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-shanghai-finance-1-pub-internal.aliyuncs.com" \
      "cn-shanghai-finance-1"

    When call run_set_backup_config_env

    The output should include "region=cn-shanghai-finance-1"
    The output should include "endpoint=https://oss-cn-shanghai-finance-1-pub-internal.aliyuncs.com"
    The status should be success
  End

  It "preserves the canonical region for an Alibaba Finance Cloud dual-stack alias"
    write_datasafed_config "Alibaba" "" \
      "https://cn-shanghai-finance.oss.aliyuncs.com" \
      "cn-shanghai-finance-1"

    When call run_set_backup_config_env

    The output should include "region=cn-shanghai-finance-1"
    The output should include "endpoint=https://cn-shanghai-finance.oss.aliyuncs.com"
    The status should be success
  End

  It "preserves the canonical region for an Alibaba Finance Cloud hzjbp internal alias"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hzjbp-a-internal.aliyuncs.com" \
      "cn-hangzhou-finance"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou-finance"
    The output should include "endpoint=https://oss-cn-hzjbp-a-internal.aliyuncs.com"
    The status should be success
  End

  It "preserves the canonical region for the second Alibaba Finance Cloud hzjbp internal alias"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hzjbp-b-internal.aliyuncs.com" \
      "cn-hangzhou-finance"

    When call run_set_backup_config_env

    The output should include "region=cn-hangzhou-finance"
    The output should include "endpoint=https://oss-cn-hzjbp-b-internal.aliyuncs.com"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with a path-like host"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn/hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with a path suffix"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hangzhou.aliyuncs.com/path"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with suffix pollution"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hangzhou.aliyuncs.com.evil"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region when a supported Alibaba URL is embedded in a prefix"
    write_datasafed_config "Alibaba" "" \
      "https://prefix.example/https://oss-cn-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba public endpoint with host-prefix pollution"
    write_datasafed_config "Alibaba" "" \
      "https://evil.oss-cn-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba internal endpoint with host-prefix pollution"
    write_datasafed_config "Alibaba" "" \
      "https://evil.oss-cn-hangzhou-internal.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba internal endpoint with suffix pollution"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hangzhou-internal.aliyuncs.com.evil"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba dual-stack endpoint with host-prefix pollution"
    write_datasafed_config "Alibaba" "" \
      "https://evil.cn-hangzhou.oss.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba dual-stack endpoint with suffix pollution"
    write_datasafed_config "Alibaba" "" \
      "https://cn-hangzhou.oss.aliyuncs.com.evil"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with an empty region"
    write_datasafed_config "Alibaba" "" \
      "https://oss-.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with an invalid DNS label"
    write_datasafed_config "Alibaba" "" \
      "https://oss--cn-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with a trailing-hyphen label"
    write_datasafed_config "Alibaba" "" \
      "https://oss-cn-hangzhou-.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with an uppercase label"
    write_datasafed_config "Alibaba" "" \
      "https://oss-CN-hangzhou.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for an Alibaba endpoint with an overlong region label"
    write_datasafed_config "Alibaba" "" \
      "https://oss-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.aliyuncs.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "extracts the region from a Tencent COS endpoint"
    write_datasafed_config "TencentCOS" "" \
      "https://cos.ap-shanghai.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=ap-shanghai"
    The output should include "endpoint=https://cos.ap-shanghai.myqcloud.com"
    The status should be success
  End

  It "extracts the region from a Tencent HTTP COS endpoint"
    write_datasafed_config "TencentCOS" "" \
      "http://cos.ap-shanghai.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=ap-shanghai"
    The output should include "endpoint=http://cos.ap-shanghai.myqcloud.com"
    The status should be success
  End

  It "keeps the configured region for a Tencent global acceleration endpoint"
    write_datasafed_config "TencentCOS" "" \
      "https://cos.accelerate.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent HTTP global acceleration endpoint"
    write_datasafed_config "TencentCOS" "" \
      "http://cos.accelerate.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent private acceleration endpoint"
    write_datasafed_config "TencentCOS" "" \
      "https://cos-internal.accelerate.tencentcos.cn"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent HTTP private acceleration endpoint"
    write_datasafed_config "TencentCOS" "" \
      "http://cos-internal.accelerate.tencentcos.cn"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent endpoint with a path-like host"
    write_datasafed_config "TencentCOS" "" \
      "https://cos.ap/shanghai.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent endpoint with suffix pollution"
    write_datasafed_config "TencentCOS" "" \
      "https://cos.ap-shanghai.myqcloud.com.evil"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent endpoint with host-prefix pollution"
    write_datasafed_config "TencentCOS" "" \
      "https://evil.cos.ap-shanghai.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent endpoint with an empty region"
    write_datasafed_config "TencentCOS" "" \
      "https://cos..myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent endpoint with an invalid DNS label"
    write_datasafed_config "TencentCOS" "" \
      "https://cos.-ap-shanghai.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps the configured region for a Tencent endpoint with an overlong region label"
    write_datasafed_config "TencentCOS" "" \
      "https://cos.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.myqcloud.com"

    When call run_set_backup_config_env

    The output should include "region=initial-region"
    The status should be success
  End

  It "keeps Minio provider fallback when force_path_style is absent"
    write_datasafed_config "Minio" ""

    When call run_set_backup_config_env

    The output should include "force_path_style=true"
    The status should be success
  End

  It "normalizes a Minio endpoint without a scheme before provider handling"
    write_datasafed_config "Minio" "" \
      "minio.example.com"

    When call run_set_backup_config_env

    The output should include "force_path_style=true"
    The output should include "endpoint=https://minio.example.com"
    The status should be success
  End

  run_sync_pbm_storage_config_with_stale_force_path_style() {
    source ../dataprotection/common-scripts.sh
    export PBM_MONGODB_URI="mongodb://mongodb.example/admin"
    export S3_REGION="us-east-1"
    export S3_ENDPOINT="http://minio.example.com"
    export S3_BUCKET="mongodb-bucket"
    export S3_PREFIX="mongodb-test/pbm"
    export S3_ACCESS_KEY="access-key"
    export S3_SECRET_KEY="secret-key"
    export S3_FORCE_PATH_STYLE="true"

    pbm() {
      if [[ "$*" == *"-o json"* ]]; then
        cat <<'EOF'
{"storage":{"s3":{"region":"us-east-1","endpointUrl":"http://minio.example.com","bucket":"mongodb-bucket","prefix":"mongodb-test/pbm","forcePathStyle":false}}}
EOF
      else
        cat > "$PBM_CONFIG_FILE"
      fi
    }

    sync_pbm_storage_config
    cat "$PBM_CONFIG_FILE"
  }

  It "rewrites PBM storage config when only forcePathStyle changed"
    When call run_sync_pbm_storage_config_with_stale_force_path_style

    The output should include "INFO: Current PBM storage forcePathStyle: false"
    The output should include "forcePathStyle: true"
    The status should be success
  End
End
