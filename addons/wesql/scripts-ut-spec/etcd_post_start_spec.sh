# shellcheck shell=bash

Describe "etcd-post-start.sh script tests"

  Describe "when LOCAL_ETCD_POD_FQDN is set"
    setup() {
      LOCAL_ETCD_POD_FQDN="etcd1,etcd2"
      LOCAL_ETCD_PORT="2379"
      CELL="zone1"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="3"
    }
    Before "setup"
    etcdctl() {
      echo "$*"
      return 0
    }

    It "generates the correct endpoints"
      When run source ../scripts/etcd-post-start.sh
      The output should include "http://etcd1:2379,http://etcd2:2379"
    End
  End

  Describe "when SERVICE_ETCD_ENDPOINT is set"
    setup() {
      SERVICE_ETCD_ENDPOINT="http://etcd1:2379,http://etcd2:2379"
      CELL="zone1"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="3"
    }
    Before "setup"
    etcdctl() {
      echo "$*"
      return 0
    }

    It "uses the SERVICE_ETCD_ENDPOINT"
      When run source ../scripts/etcd-post-start.sh
      The output should include "http://etcd1:2379,http://etcd2:2379"
    End
  End

  Describe "when both LOCAL_ETCD_POD_FQDN and SERVICE_ETCD_ENDPOINT are empty"
    setup() {
      CELL="zone1"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="3"
    }
    Before "setup"

    It "exits with an error message"
      When run source ../scripts/etcd-post-start.sh
      The output should include "Both LOCAL_POD_ETCD_LIST and SERVICE_ETCD_ENDPOINT are empty. Cannot proceed."
      The status should be failure
    End
  End

  Describe "when ETCDCTL_API is 2"
    setup() {
      LOCAL_ETCD_POD_FQDN="etcd1,etcd2"
      LOCAL_ETCD_PORT="2379"
      CELL="zone1"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="2"
    }
    Before "setup"

    etcdctl() {
      if [[ "$*" == *"get"* ]]; then
        return 1
      fi
      echo "$*"
      return 0
    }

    vtctl() {
      echo "$*"
      return 0
    }
    It "creates directories in etcd"
      When run source ../scripts/etcd-post-start.sh
      The status should be success
      The output should include "add /vitess/test-namespace/test-cluster/global"
      The output should include "add /vitess/test-namespace/test-cluster/zone1"
    End
  End

  Describe "when ETCDCTL_API is 3"
    setup() {
      LOCAL_ETCD_POD_FQDN="etcd1,etcd2"
      LOCAL_ETCD_PORT="2379"
      CELL="zone1"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="3"
    }
    Before "setup"

    etcdctl() {
      echo "$*"
      return 0
    }
    It "does not create directories in etcd"
      When run source ../scripts/etcd-post-start.sh
      The output should not include "add /vitess/test-namespace/test-cluster/global"
      The output should not include "add /vitess/test-namespace/test-cluster/zone1"
    End
  End
End