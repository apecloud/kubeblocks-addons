# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "initialize_patch_configmap_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Minio startup bash script tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/startup.sh

  init() {
    replicas_history_file="./replicas_history"
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $replicas_history_file;
  }
  AfterAll 'cleanup'

  Describe "init_buckets()"
    setup() {
      bucket_dir="./data"
      mkdir -p "$bucket_dir"
    }
    Before "setup"

    un_setup() {
      rm -rf "$bucket_dir"
    }
    After "un_setup"

    It "creates directories for the specified buckets"
      When call init_buckets "bucket1,bucket2,bucket3"
      The output should include "Successfully init bucket: $bucket_dir/bucket1"
      The output should include "Successfully init bucket: $bucket_dir/bucket2"
      The output should include "Successfully init bucket: $bucket_dir/bucket3"
      The directory "$bucket_dir/bucket1" should be exist
      The directory "$bucket_dir/bucket2" should be exist
      The directory "$bucket_dir/bucket3" should be exist
    End
  End

  Describe "read_replicas_history()"
    setup() {
      replicas_history_file="./replicas_history"
      echo "[2,4,6]" > "$replicas_history_file"
    }
    Before "setup"

    un_setup() {
      rm -f "$replicas_history_file"
    }
    After "un_setup"

    It "reads the replicas history from the specified file"
      When call read_replicas_history "$replicas_history_file"
      The output should eq "2,4,6"
    End
  End

  Describe "generate_server_pool()"
    setup() {
      export HTTP_PROTOCOL="http"
      export MINIO_COMPONENT_NAME="minio-minio"
      export CLUSTER_NAMESPACE="default"
      export CLUSTER_DOMAIN="cluster.local"
    }
    Before "setup"

    un_setup() {
      unset HTTP_PROTOCOL
      unset MINIO_COMPONENT_NAME
      unset CLUSTER_NAMESPACE
      unset CLUSTER_DOMAIN
    }
    After "un_setup"

    It "generates the server pool based on the replicas"
      When call generate_server_pool "2,4,6"
      The output should eq " http://minio-minio-{0...1}.minio-minio-headless.default.svc.cluster.local/data http://minio-minio-{2...3}.minio-minio-headless.default.svc.cluster.local/data http://minio-minio-{4...5}.minio-minio-headless.default.svc.cluster.local/data"
    End
  End

  Describe "build_startup_cmd()"
    setup() {
      export HTTP_PROTOCOL="http"
      export MINIO_COMPONENT_NAME="minio"
      export MINIO_BUCKETS="bucket1,bucket2"
      export CERTS_PATH="/certs"
      export MINIO_API_PORT="9000"
      export MINIO_CONSOLE_PORT="9001"
      export CLUSTER_DOMAIN="cluster.local"
      replicas_history_file="./replicas_history"
      echo "[1,3,5]" > "$replicas_history_file"
    }
    Before "setup"

    un_setup() {
      unset HTTP_PROTOCOL
      unset MINIO_COMPONENT_NAME
      unset MINIO_BUCKETS
      unset CERTS_PATH
      unset MINIO_API_PORT
      unset MINIO_CONSOLE_PORT
      unset CLUSTER_DOMAIN
      rm -f "$replicas_history_file"
    }
    After "un_setup"

    It "builds the startup command with the generated server pool"
      init_buckets() {
        return 0
      }

      When call build_startup_cmd
      The stderr should include "the minio replicas history is 1,3,5"
      The output should eq "/usr/bin/docker-entrypoint.sh minio server  http://minio-{0...0}.minio-headless..svc.cluster.local/data http://minio-{1...2}.minio-headless..svc.cluster.local/data http://minio-{3...4}.minio-headless..svc.cluster.local/data -S /certs --address :9000 --console-address :9001"
      The status should be success
    End

    It "returns status 1 when replicas history file does not exist"
      replicas_history_file="/nonexistent"

      When run build_startup_cmd
      The stderr should include "minio config don't existed"
      The status should be failure
    End
  End

  Describe "startup()"
    It "exits with status 1 when failed to build startup command"
      build_startup_cmd() {
        return 1
      }

      When run startup
      The stderr should include "Failed to build startup command"
      The status should be failure
    End
  End
End