# shellcheck shell=bash

Describe "vtctld.sh script tests"

  setup() {
    export LOCAL_ETCD_POD_FQDN="etcd1,etcd2"
    export LOCAL_ETCD_PORT="2379"
    export SERVICE_ETCD_ENDPOINT="etcd-service:2379"
    export CELL="zone1"
    export VTCTLD_GRPC_PORT="15999"
    export VTCTLD_WEB_PORT="15000"
    export KB_NAMESPACE="namespace"
    export KB_CLUSTER_NAME="cluster"
    export VTDATAROOT="/var/lib/vitess"
  }
  Before "setup"

  cleanup() {
    unset LOCAL_ETCD_POD_FQDN
    unset LOCAL_ETCD_PORT
    unset SERVICE_ETCD_ENDPOINT
    unset CELL
    unset VTCTLD_GRPC_PORT
    unset VTCTLD_WEB_PORT
    unset KB_NAMESPACE
    unset KB_CLUSTER_NAME
    unset VTDATAROOT
  }
  After "cleanup"

  Describe "etcd endpoints setup"
    It "sets endpoints from LOCAL_ETCD_POD_FQDN"
      When run source ../scripts/vtctld.sh
      The status should be failure
      The output should include "etcd1:2379,etcd2:2379"
      The stderr should include "No such file or directory"
    End

    It "sets endpoints from SERVICE_ETCD_ENDPOINT"
      unset LOCAL_ETCD_POD_FQDN
      When run source ../scripts/vtctld.sh
      The status should be failure
      The output should include "etcd-service:2379"
      The stderr should include "No such file or directory"
    End

    It "fails when no endpoints are set"
      unset LOCAL_ETCD_POD_FQDN 
      unset SERVICE_ETCD_ENDPOINT
      When run source ../scripts/vtctld.sh
      The status should be failure
      The output should include "Both LOCAL_ETCD_POD_FQDN and SERVICE_ETCD_ENDPOINT are empty. Cannot proceed."
    End
  End

End