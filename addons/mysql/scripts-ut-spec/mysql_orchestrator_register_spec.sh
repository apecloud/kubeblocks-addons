# shellcheck shell=bash
# shellcheck disable=SC2034

# validate shell version
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "mysql_orchestrator_register_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# Generate common library
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "MySQL Orchestrator Registration Tests"
  Include $common_library_file
  Include ../scripts/mysql-orchestrator-register.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "validate_env_vars()"
    Context "when required environment variables are not set"
      It "exits with error when ORC_ENDPOINTS is not set"
        unset ORC_ENDPOINTS
        export ORC_PORTS="3000"
        export MYSQL_POD_FQDN_LIST="mysql-0"
        export KB_CLUSTER_COMP_NAME="test"
        export KB_NAMESPACE="default"
        
        When run validate_env_vars
        The status should be failure
        The stderr should include "Required environment variables ORC_ENDPOINTS or ORC_PORTS not set"
      End

      It "exits with error when MYSQL_POD_FQDN_LIST is not set"
        export ORC_ENDPOINTS="orc:3000"
        export ORC_PORTS="3000"
        unset MYSQL_POD_FQDN_LIST
        export KB_CLUSTER_COMP_NAME="test"
        export KB_NAMESPACE="default"
        
        When run validate_env_vars
        The status should be failure
        The stderr should include "Required environment variable MYSQL_POD_FQDN_LIST not set"
      End
    End

    Context "when all required environment variables are set"
      It "succeeds with valid environment variables"
        export ORC_ENDPOINTS="orc:3000"
        export ORC_PORTS="3000"
        export MYSQL_POD_FQDN_LIST="mysql-0"
        export KB_CLUSTER_COMP_NAME="test"
        export KB_NAMESPACE="default"
        
        When call validate_env_vars
        The status should be success
      End
    End
  End

  Describe "get_orchestrator_endpoint()"
    It "returns correct endpoint"
      export ORC_ENDPOINTS="orc.default:3000"
      export ORC_PORTS="3306"
      
      When call get_orchestrator_endpoint
      The output should eq "orc.default:3306"
    End
  End

  Describe "get_first_mysql_instance()"
    It "returns correct first instance FQDN"
      export MYSQL_POD_FQDN_LIST="mysql-0,mysql-1,mysql-2"
      export KB_CLUSTER_COMP_NAME="test"
      export KB_NAMESPACE="default"
      
      When call get_first_mysql_instance
      The output should eq "test-mysql-0.default"
    End
  End

  Describe "register_to_orchestrator()"
    Context "when registration succeeds"
      curl() {
        echo "200"
      }

      It "successfully registers instance"
        When call register_to_orchestrator "test-mysql-0.default"
        The status should be success
        The output should include "Registration successful for test-mysql-0.default"
      End
    End

    Context "when registration times out"
      curl() {
        echo "404"
      }

      It "exits with error on timeout"
        When run register_to_orchestrator "test-mysql-0.default"
        The status should be failure
        The stderr should include "Timeout waiting for test-mysql-0.default to become available"
      End
    End
  End

  Describe "register_first_mysql_instance()"
    Context "when registration succeeds"
      curl() {
        echo "200"
      }

      It "successfully registers first instance"
        export ORC_ENDPOINTS="orc:3000"
        export ORC_PORTS="3306"
        export MYSQL_POD_FQDN_LIST="mysql-0,mysql-1"
        export KB_CLUSTER_COMP_NAME="test"
        export KB_NAMESPACE="default"

        When call register_first_mysql_instance
        The status should be success
        The output should include "First MySQL instance registered successfully"
      End
    End

    Context "when getting first instance fails"
      It "exits with error when MYSQL_POD_FQDN_LIST is empty"
        export ORC_ENDPOINTS="orc:3000"
        export ORC_PORTS="3306"
        export MYSQL_POD_FQDN_LIST=""
        export KB_CLUSTER_COMP_NAME="test"
        export KB_NAMESPACE="default"

        When run register_first_mysql_instance
        The status should be failure
        The stderr should include "Failed to get first MySQL instance FQDN"
      End
    End
  End

End 