# shellcheck shell=bash
# shellcheck disable=SC2034

# Validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "neon_compute_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe 'Neon Compute Script Tests'
  # Load the script to be tested
  Include ../scripts/compute.sh

  Describe 'check_required_env'
    setup() {
      unset NEON_PAGESERVER_POD_FQDN_LIST
      unset NEON_SAFEKEEPERS_POD_FQDN_LIST
      unset NEON_SAFEKEEPERS_PORT
    }

    BeforeEach 'setup'

    It 'fails when all required variables are missing'
      When call check_required_env
      The status should be failure
      The stderr should include 'Missing required environment variables'
    End

    It 'fails when only NEON_PAGESERVER_POD_FQDN_LIST is set'
      NEON_PAGESERVER_POD_FQDN_LIST='pageserver1'
      When call check_required_env
      The status should be failure
      The stderr should include 'NEON_SAFEKEEPERS_POD_FQDN_LIST'
      The stderr should include 'NEON_SAFEKEEPERS_PORT'
    End

    It 'fails when only NEON_SAFEKEEPERS_POD_FQDN_LIST is set'
      NEON_SAFEKEEPERS_POD_FQDN_LIST='safekeeper1'
      When call check_required_env
      The status should be failure
      The stderr should include 'NEON_PAGESERVER_POD_FQDN_LIST'
      The stderr should include 'NEON_SAFEKEEPERS_PORT'
    End

    It 'succeeds when all required variables are set'
      NEON_PAGESERVER_POD_FQDN_LIST='pageserver1'
      NEON_SAFEKEEPERS_POD_FQDN_LIST='safekeeper1'
      NEON_SAFEKEEPERS_PORT='5432'
      NEON_PAGESERVER_PGPORT='1111'
      NEON_PAGESERVER_HTTPPORT='2222'
      When call check_required_env
      The status should be success
    End

    It 'succeeds with multiple pageservers and safekeepers'
      NEON_PAGESERVER_POD_FQDN_LIST='pageserver1,pageserver2,pageserver3'
      NEON_SAFEKEEPERS_POD_FQDN_LIST='safekeeper1,safekeeper2,safekeeper3'
      NEON_SAFEKEEPERS_PORT='5432'
      NEON_PAGESERVER_PGPORT='1111'
      NEON_PAGESERVER_HTTPPORT='2222'
      When call check_required_env
      The status should be success
    End
  End

  Describe 'setup_directories'
    setup() {
      # Create temp test directory
      TEST_ROOT=$(mktemp -d)

      # Backup original values
      ORIG_PGDATA_DIR="$PGDATA_DIR"
      ORIG_SPEC_DIR="$SPEC_DIR"
      ORIG_SPEC_FILE="$SPEC_FILE"
      ORIG_SPEC_FILE_DOCKER="$SPEC_FILE_DOCKER"
      ORIG_SPEC_FILE_SOURCE="$SPEC_FILE_SOURCE"
      ORIG_SPEC_FILE_DOCKER_SOURCE="$SPEC_FILE_DOCKER_SOURCE"

      # Set test paths
      PGDATA_DIR="$TEST_ROOT/data/pgdata"
      SPEC_DIR="$TEST_ROOT/data/spec"
      SPEC_FILE="$TEST_ROOT/data/spec/spec.json"
      SPEC_FILE_DOCKER="$TEST_ROOT/data/spec/spec.prep.DOCKER.json"

      # Create test config directory and files
      mkdir -p "$TEST_ROOT/config"
      SPEC_FILE_SOURCE="$TEST_ROOT/config/spec.json"
      SPEC_FILE_DOCKER_SOURCE="$TEST_ROOT/config/spec.prep.DOCKER.json"
      echo "test" > "$SPEC_FILE_SOURCE"
      echo "test" > "$SPEC_FILE_DOCKER_SOURCE"
    }

    cleanup() {
      # Restore original values
      PGDATA_DIR="$ORIG_PGDATA_DIR"
      SPEC_DIR="$ORIG_SPEC_DIR"
      SPEC_FILE="$ORIG_SPEC_FILE"
      SPEC_FILE_DOCKER="$ORIG_SPEC_FILE_DOCKER"
      SPEC_FILE_SOURCE="$ORIG_SPEC_FILE_SOURCE"
      SPEC_FILE_DOCKER_SOURCE="$ORIG_SPEC_FILE_DOCKER_SOURCE"

      # Clean up test directory
      rm -rf "$TEST_ROOT"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'creates directories and copies files when PGDATA_DIR does not exist'
      When call setup_directories
      The status should be success
      The path "$PGDATA_DIR" should be directory
      The path "$SPEC_DIR" should be directory
      The path "$SPEC_FILE" should be file
      The path "$SPEC_FILE_DOCKER" should be file
      Assert [ -w "$SPEC_FILE" ]
      Assert [ -w "$SPEC_FILE_DOCKER" ]
    End

    It 'skips creation when PGDATA_DIR exists'
      mkdir -p "$PGDATA_DIR"
      When call setup_directories
      The status should be success
      The output should include "$PGDATA_DIR already exists"
    End

    It 'fails when PGDATA_DIR is not writable'
      mkdir -p "$TEST_ROOT"
      chmod -w "$TEST_ROOT"
      When call setup_directories
      The status should be failure
      The stderr should include "Failed to create pgdata directory"
      chmod +w "$TEST_ROOT"
    End

    It 'fails when source config directory does not exist'
      rm -rf "$TEST_ROOT/config"
      When call setup_directories
      The status should be success
      The stderr should include "No such file or directory"
    End

    It 'fails when source spec files do not exist'
      rm -f "$SPEC_FILE_SOURCE" "$SPEC_FILE_DOCKER_SOURCE"
      When call setup_directories
      The status should be success
      The stderr should include "No such file or directory"
    End
  End

  Describe 'build_pageserver_string'
    It 'returns multiple pageservers correctly'
      NEON_PAGESERVER_POD_FQDN_LIST='server1,server2,server3'
      When call build_pageserver_string
      The output should eq 'server1,server2,server3'
    End
  End

  Describe 'build_safekeepers_string'
    It 'builds safekeeper string with port'
      NEON_SAFEKEEPERS_POD_FQDN_LIST='keeper1,keeper2'
      NEON_SAFEKEEPERS_PORT='5432'
      When call build_safekeepers_string
      The output should eq 'keeper1:5432,keeper2:5432'
    End

    It 'handles empty input'
      NEON_SAFEKEEPERS_POD_FQDN_LIST=''
      NEON_SAFEKEEPERS_PORT='5432'
      When call build_safekeepers_string
      The output should eq ''
    End
  End

  Describe 'wait_for_pageserver'
    setup() {
      # Mock nc command
      nc() { return 0; }
      export -f nc
    }

    BeforeEach 'setup'

    It 'fails with empty pageserver'
      When call wait_for_pageserver ""
      The status should be failure
      The stderr should include "Empty pageserver address"
    End

    It 'succeeds when pageserver is available'
      NEON_PAGESERVER_PGPORT=5432
      When call wait_for_pageserver "pageserver1,pageserver2"
      The status should be success
      The output should include "Page server is ready"
    End
  End

  Describe 'create_tenant'
    setup() {
      # Mock curl command
      curl() { echo '"tenant-123"'; return 0; }
      export -f curl
    }

    BeforeEach 'setup'

    It 'returns existing TENANT if set'
      TENANT="existing-tenant"
      When call create_tenant
      The output should eq "existing-tenant"
    End

    It 'fails when PAGESERVER is not set'
      PAGESERVER=""
      When call create_tenant
      The status should be failure
      The stderr should include "PAGESERVER is not set"
    End

    It 'creates new tenant successfully'
      PAGESERVER="pageserver1"
      NEON_PAGESERVER_HTTPPORT=8080
      When call create_tenant
      The output should eq "tenant-123"
    End
  End

  Describe 'create_timeline'
    setup() {
      # Mock curl command
      curl() {
        echo '{"tenant_id":"tenant-123","timeline_id":"timeline-456"}';
        return 0;
      }
      export -f curl
    }

    BeforeEach 'setup'

    It 'fails with empty tenant_id'
      When call create_timeline ""
      The status should be failure
      The stderr should include "tenant_id is required"
    End

    It 'returns existing TIMELINE if set and CREATE_BRANCH is not set'
      TIMELINE="existing-timeline"
      When call create_timeline "tenant-123"
      The output should eq "existing-timeline"
    End

    It 'creates new timeline successfully'
      PAGESERVER="pageserver1"
      NEON_PAGESERVER_HTTPPORT=8080
      PG_VERSION=14
      When call create_timeline "tenant-123"
      The output should include "tenant-123"
      The output should include "timeline-456"
    End

    It 'creates branch timeline when CREATE_BRANCH is set'
      PAGESERVER="pageserver1"
      NEON_PAGESERVER_HTTPPORT=8080
      PG_VERSION=14
      TIMELINE="parent-timeline"
      CREATE_BRANCH="true"
      When call create_timeline "tenant-123"
      The output should include "tenant-123"
      The output should include "timeline-456"
    End
  End

  Describe 'update_spec_file'
    setup() {
      TEST_ROOT=$(mktemp -d)
      SPEC_FILE_DOCKER="$TEST_ROOT/spec.prep.DOCKER.json"
      SPEC_FILE="$TEST_ROOT/spec.json"
      echo '{"tenant":"TENANT_ID","timeline":"TIMELINE_ID","pageserver":"PAGESERVER_SPEC","safekeepers":"SAFEKEEPERS_SPEC"}' > "$SPEC_FILE_DOCKER"
    }

    cleanup() {
      rm -rf "$TEST_ROOT"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'fails when parameters are missing'
      When call update_spec_file "" "" "" ""
      The status should be failure
      The stderr should include "Missing required parameters"
    End

    It 'updates spec file successfully'
      When call update_spec_file "tenant-123" "timeline-456" "pageserver1" "safekeeper1:5432"
      The status should be success
      The contents of file "$SPEC_FILE" should include "tenant-123"
      The contents of file "$SPEC_FILE" should include "timeline-456"
      The contents of file "$SPEC_FILE" should include "pageserver1"
      The contents of file "$SPEC_FILE" should include "safekeeper1:5432"
    End
  End

  Describe 'start_compute_node'
    setup() {
      # Mock compute_ctl command
      compute_ctl() { return 0; }
      export -f compute_ctl
    }

    BeforeEach 'setup'

    It 'fails when spec file does not exist'
      SPEC_FILE="/nonexistent/spec.json"
      When call start_compute_node
      The status should be failure
      The stderr should include "Spec file not found"
    End
  End

  Describe 'show_environment_info'
    setup() {
      TEST_ROOT=$(mktemp -d)
      SPEC_FILE="$TEST_ROOT/spec.json"
      echo "test spec" > "$SPEC_FILE"
    }

    cleanup() {
      rm -rf "$TEST_ROOT"
    }

    BeforeEach 'setup'
    AfterEach 'cleanup'

    It 'fails when spec file does not exist'
      SPEC_FILE="/nonexistent/spec.json"
      When call show_environment_info
      The status should be failure
      The stderr should include "Spec file not found"
    End
  End
End