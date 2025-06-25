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
    
    # Mock error_exit function
    error_exit() {
      echo "ERROR: $1" >&2
      return 1
    }
  }
  BeforeAll "init"

  cleanup() {
    unset ETCD_VERSION
    rm -f $common_library_file
    unset -f error_exit inject_bash
  }
  AfterAll 'cleanup'

  # Load the common library
  Include $common_library_file
  
  # Define inject_bash function with proper validation
  inject_bash() {
    local version="$1"
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

    # <=3.3 || <= 3.4.22 || <=3.5.6 all base on debian image
    if [ "$major" -lt 3 ] ||
      { [ "$major" -eq 3 ] &&
        { [ "$minor" -le 3 ] ||
          { [ "$minor" -eq 4 ] && [ "$patch" -le 22 ]; } ||
          { [ "$minor" -eq 5 ] && [ "$patch" -le 6 ]; }; }; }; then
      echo "No need to inject bash for etcd-${version} image"
    else
      echo "etcd-$version image build with distroless, injecting binaries to run scripts"
    fi
  }

  Describe "inject_bash() function"
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

    It "requires injection for newer ETCD_VERSION"
      When call inject_bash "3.5.7"
      The status should be success
      The stdout should include "etcd-3.5.7 image build with distroless, injecting binaries to run scripts"
    End

    It "handles boundary version 3.5.6 correctly"
      When call inject_bash "3.5.6"
      The status should be success
      The stdout should include "No need to inject bash for etcd-3.5.6 image"
    End

    It "handles boundary version 3.5.7 correctly"
      When call inject_bash "3.5.7"
      The status should be success
      The stdout should include "etcd-3.5.7 image build with distroless, injecting binaries to run scripts"
    End
  End
End
