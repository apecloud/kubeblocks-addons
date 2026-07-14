# shellcheck shell=bash

Describe "OceanBase CE object storage endpoint handling"
  Include ../dataprotection/common-scripts.sh

  getent() {
    if [ "$1" = "hosts" ] && [ "$2" = "multi.oceanbase-ce-test.svc" ]; then
      echo "10.99.171.87 $2"
      echo "10.99.171.88 $2"
      return 0
    fi
    if [ "$1" = "hosts" ] && [ "$2" = "ipv6-only.oceanbase-ce-test.svc" ]; then
      echo "fd00::10 $2"
      return 0
    fi
    if [ "$1" = "hosts" ] && [ "$2" = "mixed-invalid.oceanbase-ce-test.svc" ]; then
      echo "01.002.003.004 $2"
      echo "999.1.1.1 $2"
      echo "fd00::10 $2"
      echo "10.99.171.89 $2"
      return 0
    fi
    if [ "$1" = "hosts" ] && [ "$2" = "invalid-only.oceanbase-ce-test.svc" ]; then
      echo "01.002.003.004 $2"
      echo "999.1.1.1 $2"
      return 0
    fi
    if [ "$1" = "hosts" ] && [ "$2" = "partial-failure.oceanbase-ce-test.svc" ]; then
      echo "10.99.171.90 $2"
      return 2
    fi
    if [ "$1" = "hosts" ] && {
      [ "$2" = "minio-pre.oceanbase-ce-test.svc" ] ||
        [ "$2" = "minio-pre.oceanbase-ce-test.svc.cluster.local" ]
    }; then
      echo "10.99.171.87 $2"
      return 0
    fi
    return 2
  }

  It "preserves HTTP while resolving a Kubernetes service endpoint"
    When call replaceK8sSVC "http://minio-pre.oceanbase-ce-test.svc:9000"
    The output should eq "http://10.99.171.87:9000"
    The status should be success
  End

  It "preserves HTTPS while resolving a Kubernetes service endpoint"
    When call replaceK8sSVC "https://minio-pre.oceanbase-ce-test.svc:9000"
    The output should eq "https://10.99.171.87:9000"
    The status should be success
  End

  It "keeps a scheme-less Kubernetes service endpoint scheme-less"
    When call replaceK8sSVC "minio-pre.oceanbase-ce-test.svc:9000"
    The output should eq "10.99.171.87:9000"
    The status should be success
  End

  It "resolves a fully qualified Kubernetes service endpoint"
    When call replaceK8sSVC "http://minio-pre.oceanbase-ce-test.svc.cluster.local:9000"
    The output should eq "http://10.99.171.87:9000"
    The status should be success
  End

  It "preserves the original endpoint when service DNS lookup fails"
    When call replaceK8sSVC "http://missing.oceanbase-ce-test.svc:9000"
    The output should eq "http://missing.oceanbase-ce-test.svc:9000"
    The status should be success
  End

  It "selects one IPv4 address when service DNS returns multiple addresses"
    When call replaceK8sSVC "http://multi.oceanbase-ce-test.svc:9000"
    The output should eq "http://10.99.171.87:9000"
    The status should be success
  End

  It "preserves the original endpoint when service DNS returns only IPv6"
    When call replaceK8sSVC "http://ipv6-only.oceanbase-ce-test.svc:9000"
    The output should eq "http://ipv6-only.oceanbase-ce-test.svc:9000"
    The status should be success
  End

  It "skips malformed and IPv6 candidates before selecting a canonical IPv4"
    When call replaceK8sSVC "http://mixed-invalid.oceanbase-ce-test.svc:9000"
    The output should eq "http://10.99.171.89:9000"
    The status should be success
  End

  It "preserves the original endpoint when no canonical IPv4 is available"
    When call replaceK8sSVC "http://invalid-only.oceanbase-ce-test.svc:9000"
    The output should eq "http://invalid-only.oceanbase-ce-test.svc:9000"
    The status should be success
  End

  It "preserves the original endpoint when DNS emits an address then fails"
    When call replaceK8sSVC "http://partial-failure.oceanbase-ce-test.svc:9000"
    The output should eq "http://partial-failure.oceanbase-ce-test.svc:9000"
    The status should be success
  End

  It "preserves an external endpoint exactly"
    When call replaceK8sSVC "https://storage.example.com"
    The output should eq "https://storage.example.com"
    The status should be success
  End

  It "builds the exact OceanBase S3 destination URL with the endpoint scheme"
    endpoint="http://minio-pre.oceanbase-ce-test.svc:9000"
    provider="MinIO"
    bucket="kb-backups"
    access_key_id="access"
    secret_access_key="secret"
    DP_BACKUP_BASE_PATH="/oceanbase-ce"

    When call getDestURL data tenant 1001
    The output should eq "s3://kb-backups/oceanbase-ce/tenant/1001?host=http://10.99.171.87:9000&access_id=access&access_key=secret"
    The status should be success
  End

  It "keeps the OSS destination prefix for an explicit HTTPS endpoint"
    endpoint="https://oss-cn-test.aliyuncs.com"
    provider="Alibaba"
    bucket="ob-backups"
    access_key_id="access"
    secret_access_key="secret"
    DP_BACKUP_BASE_PATH="/oceanbase-ce"

    When call getDestURL data tenant 1001
    The output should eq "oss://ob-backups/oceanbase-ce/tenant/1001?host=https://oss-cn-test.aliyuncs.com&access_id=access&access_key=secret"
    The status should be success
  End

  It "keeps the COS destination prefix for an explicit HTTPS endpoint"
    endpoint="https://cos.ap-test.myqcloud.com"
    provider="TencentCOS"
    bucket="ob-backups"
    access_key_id="access"
    secret_access_key="secret"
    DP_BACKUP_BASE_PATH="/oceanbase-ce"

    When call getDestURL data tenant 1001
    The output should eq "cos://ob-backups/oceanbase-ce/tenant/1001?host=https://cos.ap-test.myqcloud.com&access_id=access&access_key=secret"
    The status should be success
  End
End
