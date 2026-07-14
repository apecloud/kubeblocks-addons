# shellcheck shell=bash

Describe "OceanBase CE object storage endpoint handling"
  Include ../dataprotection/common-scripts.sh

  Mock getent
    if [ "$1" = "hosts" ] && {
      [ "$2" = "minio-pre.oceanbase-ce-test.svc" ] ||
        [ "$2" = "minio-pre.oceanbase-ce-test.svc.cluster.local" ]
    }; then
      echo "10.99.171.87 $2"
      return 0
    fi
    return 2
  End

  It "preserves HTTP while resolving a Kubernetes service endpoint"
    When call replaceK8sSVC "http://minio-pre.oceanbase-ce-test.svc:9000"
    The output should eq "http://10.99.171.87:9000"
  End

  It "preserves HTTPS while resolving a Kubernetes service endpoint"
    When call replaceK8sSVC "https://minio-pre.oceanbase-ce-test.svc:9000"
    The output should eq "https://10.99.171.87:9000"
  End

  It "keeps a scheme-less Kubernetes service endpoint scheme-less"
    When call replaceK8sSVC "minio-pre.oceanbase-ce-test.svc:9000"
    The output should eq "10.99.171.87:9000"
  End

  It "resolves a fully qualified Kubernetes service endpoint"
    When call replaceK8sSVC "http://minio-pre.oceanbase-ce-test.svc.cluster.local:9000"
    The output should eq "http://10.99.171.87:9000"
  End

  It "preserves the original endpoint when service DNS lookup fails"
    When call replaceK8sSVC "http://missing.oceanbase-ce-test.svc:9000"
    The output should eq "http://missing.oceanbase-ce-test.svc:9000"
  End

  It "preserves an external endpoint exactly"
    When call replaceK8sSVC "https://storage.example.com"
    The output should eq "https://storage.example.com"
  End

  It "carries the endpoint scheme into the OceanBase S3 host parameter"
    endpoint="http://minio-pre.oceanbase-ce-test.svc:9000"
    provider="MinIO"
    bucket="kb-backups"
    access_key_id="access"
    secret_access_key="secret"
    DP_BACKUP_BASE_PATH="/oceanbase-ce"

    When call getDestURL data tenant 1001
    The output should include "host=http://10.99.171.87:9000"
  End
End
