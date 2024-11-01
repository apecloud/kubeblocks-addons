# shellcheck shell=bash
# shellcheck disable=SC2034

# validate shell version
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "init_mysql_instance_for_orc_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# Generate common library
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "MySQL Instance Initialization Tests"
  Include $common_library_file
  Include ../scripts/init-mysql-instance-for-orc.sh

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
      It "exits with error when MYSQL_ROOT_USER is not set"
        unset MYSQL_ROOT_USER
        export MYSQL_ROOT_PASSWORD="password"
        export ORC_TOPOLOGY_USER="orc"
        export ORC_TOPOLOGY_PASSWORD="password"
        
        When run validate_env_vars
        The status should be failure
        The stderr should include "Required environment variables MYSQL_ROOT_USER or MYSQL_ROOT_PASSWORD not set"
      End
    End
  End

  Describe "create_orc_user()"
    Context "when mysql command succeeds"
      mysql() {
        return 0
      }

      It "creates orchestrator user successfully"
        When call create_orc_user
        The status should be success
        The output should include "Created orchestrator user successfully"
      End
    End

    Context "when mysql command fails"
      mysql() {
        return 1
      }

      It "exits with error when mysql command fails"
        When run create_orc_user
        The status should be failure
        The stderr should include "Failed to create orchestrator user"
      End
    End
  End

  Describe "wait_for_mysql()"
    Context "when mysql becomes available"
      mysqladmin() {
        return 0
      }

      It "succeeds when mysql is available"
        When call wait_for_mysql
        The status should be success
        The output should include "MySQL is now available"
      End
    End

    Context "when mysql timeout occurs"
      mysqladmin() {
        return 1
      }

      It "exits with error on timeout"
        When run wait_for_mysql
        The status should be failure
        The stderr should include "Timeout waiting for MySQL to be available"
      End
    End
  End

  Describe "get_master_from_orc()"
    Context "when orchestrator returns valid topology"
      orchestrator-client() {
        echo "[ok,ok,5.7.21,rw,mod,master,GTID,GTIDMOD] master-1:3306"
      }

      It "parses master info successfully"
        When call get_master_from_orc
        The status should be success
        The variable master_from_orc should eq "master-1"
      End
    End

    Context "when orchestrator returns error"
      orchestrator-client() {
        echo "ERROR: cluster not found"
      }

      It "returns without error on orchestrator failure"
        When call get_master_from_orc
        The status should be success
        The variable master_from_orc should be undefined
      End
    End
  End

  Describe "setup_replication()"
    Context "when mysql commands succeed"
      mysql() {
        return 0
      }

      It "configures replication successfully"
        When call setup_replication "master-1"
        The status should be success
        The output should include "Configured replication successfully"
      End
    End

    Context "when mysql commands fail"
      mysql() {
        return 1
      }

      It "exits with error when mysql commands fail"
        When run setup_replication "master-1"
        The status should be failure
        The stderr should include "Failed to configure replication"
      End
    End
  End

End 