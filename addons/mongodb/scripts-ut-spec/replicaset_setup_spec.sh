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
  }
  BeforeAll "init"

  # Global cleanup.
  cleanup() {
    rm -rf "$DATA_VOLUME"
    rm -rf "$MOCK_SCRIPTS_DIR"
    unset MONGODB_ROOT
  }
  AfterAll 'cleanup'

  # Test Case 1: Normal startup (without backup file).
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
      # To make the script testable, we pass the mock script path as an argument.
      # The script under test needs to be modified slightly to accept this. See note below.
      When run source ../scripts/replicaset-setup.tpl "$MOCK_SCRIPTS_DIR"

      # Assert that the basic directory structure is created.
      The path "$DATA_VOLUME/db" should be directory
      The path "$DATA_VOLUME/logs" should be directory
      The path "$DATA_VOLUME/tmp" should be directory

      # Assert that 'exec' was called with the correct parameters by checking the log file.
      The file "$DATA_VOLUME/exec_cmd.log" should be file
      The contents of file "$DATA_VOLUME/exec_cmd.log" should equal "mongod --bind_ip_all --port 27017 --replSet cluster-mongodb --config /etc/mongodb/mongodb.conf"
      The status should be success
    End
  End

  # Test Case 2: Restore from backup (backup file exists).
  Describe "start replicaset with a backup file for restore"
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
      When run source ../scripts/replicaset-setup.tpl "$MOCK_SCRIPTS_DIR"
      
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