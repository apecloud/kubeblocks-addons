# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "init_broker_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Pulsar Init Broker Bash Script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/init-broker.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "check_env_variables()"
    It "checks if required environment variables are set"
      export zookeeperServers="localhost:2181"
      export POD_NAME="broker-0"
      export clusterName="my-cluster"
      export webServiceUrl="http://localhost:8080"
      export brokerServiceUrl="pulsar://localhost:6650"

      When run check_env_variables
      The status should be success
    End

    It "exits with status 1 when a required environment variable is not set"
      unset zookeeperServers

      When run check_env_variables
      The output should include "Error: zookeeperServers environment variable is not set, Please set the zookeeperServers environment variable and try again."
      The status should be failure
    End
  End

  Describe "wait_for_zookeeper()"
    It "waits for Zookeeper to be ready"
      python3() {
        if [ "$1" = "/kb-scripts/zookeeper.py" ] && [ "$2" = "get" ] && [ "$3" = "/" ]; then
          return 0
        fi
        return 1
      }

      When call wait_for_zookeeper "localhost:2181"
      The output should include "Waiting for Zookeeper at localhost:2181 to be ready..."
      The output should include "Zookeeper is ready"
    End
  End

  Describe "check_cluster_initialized()"
    It "returns 0 when cluster is already initialized"
      python3() {
        if [ "$1" = "/kb-scripts/zookeeper.py" ] && [ "$2" = "get" ] && [ "$3" = "/admin/clusters/my-cluster" ]; then
          return 0
        fi
        return 1
      }

      When call check_cluster_initialized "localhost:2181" "my-cluster"
      The output should include "Cluster my-cluster is already initialized"
      The status should be success
    End

    It "returns 1 when cluster is not initialized"
      python3() {
        if [ "$1" = "/kb-scripts/zookeeper.py" ] && [ "$2" = "get" ] && [ "$3" = "/admin/clusters/my-cluster" ]; then
          return 1
        fi
        return 0
      }

      When call check_cluster_initialized "localhost:2181" "my-cluster"
      The output should include "Cluster my-cluster is not initialized"
      The status should be failure
    End
  End

  Describe "wait_for_cluster_metadata()"
    It "waits for cluster metadata initialization"
      python3() {
        if [ "$1" = "/kb-scripts/zookeeper.py" ] && [ "$2" = "get" ] && [ "$3" = "/admin/clusters/my-cluster" ]; then
          return 0
        fi
      }

      When call wait_for_cluster_metadata "localhost:2181" "my-cluster"
      The output should include "Waiting for cluster metadata initialization..."
      The output should include "Cluster metadata initialized"
    End
  End

  Describe "initialize_cluster_metadata()"
    It "initializes cluster metadata"
      bin/pulsar() {
        if [ "$1" = "initialize-cluster-metadata" ]; then
          return 0
        fi
      }

      When call initialize_cluster_metadata "my-cluster" "localhost:2181" "http://localhost:8080" "pulsar://localhost:6650"
      The output should include "Initializing cluster metadata for cluster: my-cluster"
    End
  End

  Describe "init_broker()"
    It "initializes broker for the first pod"
      export zookeeperServers="localhost:2181"
      export POD_NAME="broker-0"
      export clusterName="my-cluster"
      export webServiceUrl="http://localhost:8080"
      export brokerServiceUrl="pulsar://localhost:6650"

      check_env_variables() {
        return 0
      }

      wait_for_zookeeper() {
        return 0
      }

      check_cluster_initialized() {
        return 1
      }

      initialize_cluster_metadata() {
        return 0
      }

      When run init_broker
      The status should be success
    End

    It "skips initialization for non-first pods"
      export zookeeperServers="localhost:2181"
      export POD_NAME="broker-1"
      export clusterName="my-cluster"
      export webServiceUrl="http://localhost:8080"
      export brokerServiceUrl="pulsar://localhost:6650"

      check_env_variables() {
        return 0
      }

      wait_for_zookeeper() {
        return 0
      }

      wait_for_cluster_metadata() {
        return 0
      }

      python3() {
        return 0
      }

      bin/pulsar() {
        return 0
      }

      When run init_broker
      The status should be success
      The output should include "Waiting for cluster initialize ready"
    End

    It "skips initialization if cluster is already initialized"
      export zookeeperServers="localhost:2181"
      export POD_NAME="broker-0"
      export clusterName="my-cluster"
      export webServiceUrl="http://localhost:8080"
      export brokerServiceUrl="pulsar://localhost:6650"

      check_env_variables() {
        return 0
      }

      wait_for_zookeeper() {
        return 0
      }

      check_cluster_initialized() {
        return 0
      }

      bin/pulsar() {
        return 0
      }

      When run init_broker
      The stdout should include "Cluster already initialized"
      The status should be success
    End
  End
End