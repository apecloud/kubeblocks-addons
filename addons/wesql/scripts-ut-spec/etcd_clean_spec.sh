# shellcheck shell=bash

Describe "Etcd Clean Script Tests"

  Describe "when SERVICE_ETCD_ENDPOINT is not set,"
    It "exits with status 0"
      SERVICE_ETCD_ENDPOINT=""
      When run source ../scripts/etcd-clean.sh
      The status should be success
      The output should be blank
    End
  End

  Describe "when SERVICE_ETCD_ENDPOINT is set,"
    setup() {
      SERVICE_ETCD_ENDPOINT="http://localhost:2379"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="3"
    }
    Before "setup"

    etcdctl() {
      echo "$*"
      return 0
    }

    It "prints the endpoints"
      When run source ../scripts/etcd-clean.sh
      The output should include "$SERVICE_ETCD_ENDPOINT"
    End

    It "constructs the servers variable correctly"
      When run source ../scripts/etcd-clean.sh
      The output should include "http://localhost:2379"
    End

    It "attempts to delete keys with the correct prefix"
      When run source ../scripts/etcd-clean.sh
      The output should include "Deleting all keys with prefix /vitess/test-namespace/test-cluster from Etcd server at http://localhost:2379..."
    End

    It "uses etcdctl to delete keys with the correct prefix"
      When run source ../scripts/etcd-clean.sh
      The output should include "--endpoints http://localhost:2379 del /vitess/test-namespace/test-cluster --prefix"
    End

    It "prints success message on successful deletion"
      stub() {
        return 0
      }
      BeforeCall "stub etcdctl"
      When run source ../scripts/etcd-clean.sh
      The output should include "Successfully deleted all keys with prefix /vitess/test-namespace/test-cluster."
    End

    It "prints failure message on failed deletion"
      etcdctl() {
        return 1
      }
      When run source ../scripts/etcd-clean.sh
      The output should include "Failed to delete keys. Please check your Etcd server and try again."
      The status should be failure
    End
  End

  Describe "when ETCDCTL_API is set to 2"
    setup() {
      SERVICE_ETCD_ENDPOINT="http://localhost:2379"
      KB_NAMESPACE="test-namespace"
      KB_CLUSTER_NAME="test-cluster"
      ETCDCTL_API="2"
    }
    Before "setup"

    etcdctl() {
      echo "$*" 
      return 0
    }

    It "uses etcdctl to delete keys with the correct prefix using API v2"
      When run source ../scripts/etcd-clean.sh
      The status should be success
      The output should include "--endpoints http://localhost:2379 rm -r /vitess/test-namespace/test-cluster"
    End
  End

End