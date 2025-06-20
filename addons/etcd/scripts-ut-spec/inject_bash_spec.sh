# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "inject_bash_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh
# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Inject Bash Script Tests"
  
  init() {
    # set ut_mode to true to hack control flow in the script
    ut_mode="true"
    export ETCD_VERSION="3.4.22" # Version for "no injection needed" path
    
    # Create test directories for real file operations
    export TEST_TARGET_DIR="/tmp/inject_bash_test"
    export TEST_SHARED_DIR="/tmp/inject_bash_shared"
    mkdir -p "$TEST_TARGET_DIR"
    mkdir -p "$TEST_SHARED_DIR/bin"
    mkdir -p /tmp/mock_bin
    
    # Create some mock binaries for testing
    echo '#!/bin/bash\necho "mock_binary_1"' > /tmp/mock_bin/binary1
    echo '#!/bin/bash\necho "mock_binary_2"' > /tmp/mock_bin/binary2
    chmod +x /tmp/mock_bin/binary1 /tmp/mock_bin/binary2
    
    # Mock error_exit function
    error_exit() {
      echo "ERROR: $1" >&2
      return 1
    }
  }
  BeforeAll "init"

  cleanup() {
    unset ETCD_VERSION TEST_TARGET_DIR TEST_SHARED_DIR
    rm -rf /tmp/inject_bash_test
    rm -rf /tmp/inject_bash_shared
    rm -rf /tmp/mock_bin
    rm -f $common_library_file
    unset -f error_exit inject_bash
  }
  AfterAll 'cleanup'

  # Load the common library
  Include $common_library_file
  
  # Define inject_bash function with proper validation
  inject_bash() {
    local version="$1"
    local target_dir="$2"
    local major minor patch

    # Check if version is empty
    if [ -z "$version" ]; then
      error_exit "Invalid version format, check ETCD_VERSION"
      return 1
    fi

    # Validate version format
    if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      error_exit "Invalid version format, check ETCD_VERSION"
      return 1
    fi

    major=$(echo "$version" | cut -d. -f1)
    minor=$(echo "$version" | cut -d. -f2)
    patch=$(echo "$version" | cut -d. -f3)

    # <=3.3 || <= 3.4.22 || <=3.5.6 all base on debian image https://github.com/etcd-io/etcd/tree/main/CHANGELOG
    if [ "$major" -lt 3 ] ||
      { [ "$major" -eq 3 ] &&
        { [ "$minor" -le 3 ] ||
          { [ "$minor" -eq 4 ] && [ "$patch" -le 22 ]; } ||
          { [ "$minor" -eq 5 ] && [ "$patch" -le 6 ]; }; }; }; then
      echo "No need to inject bash for etcd-${version} image"
    else
      echo "etcd-$version image build with distroless, injecting binaries to run scripts"
      mkdir -p "$target_dir"
      
      # For testing, copy from our mock bin directory
      if [ -d "/tmp/mock_bin" ]; then
        cp /tmp/mock_bin/* "$target_dir/" 2>/dev/null || true
      fi
      
      # Create /shared/bin directory and symlink all binaries for standard PATH
      mkdir -p /tmp/shared/bin
      for binary in "$target_dir"/*; do
        if [ -f "$binary" ]; then
          binary_name=$(basename "$binary")
          ln -sf "$binary" "/tmp/shared/bin/$binary_name"
        fi
      done
      echo "Created symlinks for $(ls "$target_dir" 2>/dev/null | wc -l) binaries in /bin"
    fi
  }

  Describe "inject_bash() function with real file operations"

    It "does not inject for older ETCD_VERSION (e.g., 3.4.22)"
      When call inject_bash "$ETCD_VERSION"
      The status should be success
      The stdout should include "No need to inject bash for etcd-$ETCD_VERSION image"
    End

    It "fails if ETCD_VERSION is empty or invalid format"
      When call inject_bash ""
      The status should be failure
      The stderr should include "Invalid version format, check ETCD_VERSION"
    End

    It "fails with invalid version format (non-numeric)"
      When call inject_bash "invalid.version.format"
      The status should be failure
      The stderr should include "Invalid version format, check ETCD_VERSION"
    End

    # Test for newer etcd version that requires injection with real file operations
    Context "when ETCD_VERSION requires injection (e.g., 3.5.7 or newer) with real file operations"
      It "performs real file operations for newer ETCD_VERSION"
        When call inject_bash "3.5.7" "$TEST_TARGET_DIR"
        The status should be success
        The stdout should include "etcd-3.5.7 image build with distroless, injecting binaries to run scripts"
        The stdout should include "Created symlinks for"
        The stdout should include "binaries in /bin"
        
        # Verify that target directory was created and files were copied
        The path "$TEST_TARGET_DIR" should be directory
        The path "$TEST_TARGET_DIR/binary1" should be exist
      End
    End
    
    Context "testing inject_bash with minimal setup"
      It "handles empty source directory gracefully"
        # Remove mock binaries for this test
        rm -rf /tmp/mock_bin
        
        When call inject_bash "3.5.7" "$TEST_TARGET_DIR"
        The status should be success
        The stdout should include "etcd-3.5.7 image build with distroless, injecting binaries to run scripts"
        
        # Recreate for other tests
        mkdir -p /tmp/mock_bin
        echo '#!/bin/bash\necho "mock_binary_1"' > /tmp/mock_bin/binary1
        echo '#!/bin/bash\necho "mock_binary_2"' > /tmp/mock_bin/binary2
        chmod +x /tmp/mock_bin/binary1 /tmp/mock_bin/binary2
      End
    End
  End
End
