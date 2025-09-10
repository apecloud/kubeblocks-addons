# shellcheck shell=bash
# shellcheck disable=SC2034


# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
# if ! validate_shell_type_and_version "bash" &>/dev/null; then
#   echo "mongodb replicaset_setup_spec.sh skip all cases because dependency bash is not installed."
#   exit 0
# fi


Describe "Mongodb Startup Script Tests"

  # Global setup: define variables and the path for our mock script.
  init() {
    DATA_VOLUME="./mongodb_data_test"
    # Also export MONGODB_ROOT so it's accessible to both the test and the script under test.
    export MONGODB_ROOT=${DATA_VOLUME:-/data/mongodb}
    POD_NAME="cluster-mongodb-0"
    
    # Create the directory for the dependency script the main script will 'source'.
    MOCK_SCRIPTS_DIR="./mock_scripts"
    mkdir -p "$MOCK_SCRIPTS_DIR"
    # Define a mock 'process_restore_signal' function in our mock common.sh file.
    cat > "$MOCK_SCRIPTS_DIR/mongodb-common.sh" <<'EOF'
process_restore_signal() {
  echo "Mocked process_restore_signal called with: $2"
}
EOF
    SCRIPTS_BASE_PATH="$MOCK_SCRIPTS_DIR"
  }
  BeforeAll "init"

  # Global cleanup.
  cleanup() {
    rm -rf "$DATA_VOLUME"
    rm -rf "$MOCK_SCRIPTS_DIR"
    unset MONGODB_ROOT
  }
  AfterAll 'cleanup'

  # Test Case 1: Normal startup (without any backup file).
  Describe "start replicaset without backup file"
    
    # In this scenario, we need to mock the 'exec' command.
    setup_mocks() {
      # Mock 'exec' to write the command it receives to a temp file for assertion.
      exec() {
        echo "$@" > "$DATA_VOLUME/exec_cmd.log"
      }
    }
    Before 'setup_mocks'

    # Clean up the mock function.
    cleanup_mocks() {
      unset -f exec
    }
    After 'cleanup_mocks'

    It "should create directories and exec mongod with correct parameters"
      When run source ../scripts/replicaset-setup.tpl

      The path "$DATA_VOLUME/db" should be directory
      The path "$DATA_VOLUME/logs" should be directory
      The path "$DATA_VOLUME/tmp" should be directory

      The file "$DATA_VOLUME/exec_cmd.log" should be file
      The contents of file "$DATA_VOLUME/exec_cmd.log" should equal "mongod --bind_ip_all --port 27017 --replSet cluster-mongodb --config /etc/mongodb/mongodb.conf"
      The status should be success
    End
  End

  # Test Case 2: Restore from legacy datafile (mongodb.backup exists).
  Describe "start replicaset with a legacy backup file for restore"
    BACKUPFILE="$MONGODB_ROOT/db/mongodb.backup"
    
    # Mock mongod, mongosh, kill, wait, and exec for this specific test case.
    setup_datafile_mocks() {
      mkdir -p "$MONGODB_ROOT/db"
      touch "$BACKUPFILE"
      
      # Mock the temporary mongod instance for restore
      mongod() {
        # shellcheck disable=SC2145
        echo "Mocked mongod (for restore) started with: $@"
        # The script needs a PID file to kill the process
        echo "12345" > "$MONGODB_ROOT/tmp/mongodb.pid"
      }
      
      # Mock the client. It needs to fail the readiness check once, then succeed.
      mongosh() {
        # Check if it's the readiness check from the 'until' loop
        if [[ "$*" == *"--eval print('restore process is ready')"* ]]; then
          local counter_file="$DATA_VOLUME/until_counter"
          if [ ! -f "$counter_file" ]; then
            touch "$counter_file"
            return 1 # Fail the first time to test the loop
          else
            echo "restore process is ready" # Succeed the second time
            return 0
          fi
        else
          # For all other calls (like dropUser), just log the command
          echo "Mocked mongosh called with: $*"
        fi
      }
      # Alias mongo to mongosh for robustness in test environment
      mongo() { mongosh "$@"; }
      
      # Mock system commands
      kill() { echo "Mocked kill called with PID: $1"; }
      wait() { echo "Mocked wait called for PID: $1"; }

      # The script will eventually call exec, so we mock it too.
      exec() { echo "$@" > "$DATA_VOLUME/exec_cmd.log"; }
    }
    Before 'setup_datafile_mocks'

    cleanup_datafile_mocks() {
      rm -f "$BACKUPFILE"
      rm -f "$DATA_VOLUME/until_counter"
      unset -f mongod mongosh mongo kill wait exec
    }
    After 'cleanup_datafile_mocks'
    
    It "should run restore process and then proceed to normal startup"
      When run source ../scripts/replicaset-setup.tpl
      
      # Assert the restore-specific actions
      The output should include "Mocked mongod (for restore) started with: --bind_ip_all --port 27027"
      The output should include "Mocked mongosh called with: --quiet --port 27027 local --eval db.system.replset.deleteOne({})"
      The output should include "Mocked mongosh called with: --quiet --port 27027 admin --eval db.dropUser(\"root\""
      The output should include "Mocked mongosh called with: --quiet --port 27027 admin --eval db.dropRole(\"anyAction\""
      The output should include "Mocked kill called with PID: 12345"
      The output should include "Mocked wait called for PID: 12345"
      The output should include "INFO: restore set-up configuration successfully."
      The path "$BACKUPFILE" should not be file

      # Assert that after the restore, it proceeds to the normal exec startup
      The file "$DATA_VOLUME/exec_cmd.log" should be file
      The contents of file "$DATA_VOLUME/exec_cmd.log" should equal "mongod --bind_ip_all --port 27017 --replSet cluster-mongodb --config /etc/mongodb/mongodb.conf"
      The status should be success
    End
  End

  # Test Case 3: Restore from PBM backup (mongodb_pbm.backup exists).
  Describe "start replicaset with a PBM backup file for restore"
    PBM_BACKUPFILE="$MONGODB_ROOT/tmp/mongodb_pbm.backup"
    
    # In this scenario, create the backup file and mock pbm-agent and mongod.
    setup_restore_mocks() {
      touch "$PBM_BACKUPFILE"
      # Mock pbm-agent-entrypoint.
      pbm-agent-entrypoint() {
        echo "Mocked pbm-agent-entrypoint started"
      }
      # Mock mongod (this time it's not called via 'exec', but in the background with '&').
      mongod() {
        # shellcheck disable=SC2145
        echo "Mocked mongod started with: $@"
      }
    }
    Before 'setup_restore_mocks'

    # Clean up the backup file and mock functions.
    cleanup_restore_mocks() {
      rm -f "$PBM_BACKUPFILE"
      unset -f pbm-agent-entrypoint
      unset -f mongod
    }
    After 'cleanup_restore_mocks'
    
    It "should start pbm-agent, mongod, and call restore signals"
      When run source ../scripts/replicaset-setup.tpl
      
      # Assert the output from all mock functions to confirm the correct execution flow.
      The output should include "INFO: Startup backup agent for restore."
      The output should include "Mocked pbm-agent-entrypoint started"
      The output should include "INFO: Start mongodb for restore."
      The output should include "Mocked mongod started with: --bind_ip_all --port 27017 --replSet cluster-mongodb --config /etc/mongodb/mongodb.conf"
      The output should include "Mocked process_restore_signal called with: start"
      The output should include "Mocked process_restore_signal called with: end"
      The status should be success
    End
  End
End