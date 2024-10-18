# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "initialize_patch_configmap_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Minio init container bash script Tests"
  # load the scripts to be tested and dependencies
  Include ../scripts/initialize-patch-configmap.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "get_current_cm_key_value()"
    It "returns the value of the specified key from the ConfigMap"
      kubectl() {
        echo "[1,2,3]"
      }

      When call get_current_cm_key_value "my-configmap" "my-namespace" "replicas"
      The output should eq "1,2,3"
    End
  End

  Describe "update_cm_key_value()"
    It "updates the value of the specified key in the ConfigMap"
      kubectl() {
        return 0
      }

      When call update_cm_key_value "my-configmap" "my-namespace" "replicas" "[1,2,3,4]"
      The status should be success
    End
  End

  Describe "get_cm_key_new_value()"
    It "returns the replicas value when cur is empty"
      When call get_cm_key_new_value "" "4"
      The output should eq "[4]"
    End

    It "returns the cur value when last equals replicas"
      When call get_cm_key_new_value "1,2,3" "3"
      The output should eq "[1,2,3]"
    End

    It "appends the replicas value to cur when last does not equal replicas"
      When call get_cm_key_new_value "1,2,3" "4"
      The output should eq "[1,2,3,4]"
    End
  End

  Describe "update_configmap()"
    setup() {
      export MINIO_COMPONENT_NAME="minio"
      export CLUSTER_NAMESPACE="default"
      export MINIO_COMP_REPLICAS="4"
    }
    Before "setup"

    un_setup() {
      unset MINIO_COMPONENT_NAME
      unset CLUSTER_NAMESPACE
      unset MINIO_COMP_REPLICAS
    }
    After "un_setup"

    It "updates the ConfigMap with the new replicas value"
      get_current_cm_key_value() {
        echo "1,2,3"
      }

      update_cm_key_value() {
        return 0
      }

      When run update_configmap
      The output should eq "ConfigMap minio-minio-configuration updated successfully with MINIO_REPLICAS_HISTORY=[1,2,3,4]"
    End
  End
End