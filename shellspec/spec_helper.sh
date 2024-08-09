# shellcheck shell=sh

# Defining variables and functions here will affect all specfiles.
# Change shell options inside a function may cause different behavior,
# so it is better to set them here.
# set -eu

# This callback function will be invoked only once before loading specfiles.
spec_helper_precheck() {
  # Available functions: info, warn, error, abort, setenv, unsetenv
  # Available variables: VERSION, SHELL_TYPE, SHELL_VERSION
  : minimum_version "0.28.1"
}

# This callback function will be invoked after a specfile has been loaded.
spec_helper_loaded() {
  :
}

# This callback function will be invoked after core modules has been loaded.
spec_helper_configure() {
  # Available functions: import, before_each, after_each, before_all, after_all
  : import 'support/custom_matcher'
}

# This is a global function that used to validate the shell type and version, and can be used in specfiles.
validate_shell_type_and_version() {
  expected_shell_type=$1
  expected_major_version=${2:-0}
  expected_minor_version=${3:-0}

  if [ -z "$SHELLSPEC_SHELL" ]; then
    echo "SHELLSPEC_SHELL environment variable is not set."
    return 1
  fi

  case "$expected_shell_type" in
    bash)
      shell_type=$($SHELLSPEC_SHELL --version | grep -i 'bash')
      version_output=$($SHELLSPEC_SHELL --version | head -1)
      major_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)
      minor_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1| cut -d'.' -f2)
      ;;
    ksh)
      shell_type=$($SHELLSPEC_SHELL --version 2>&1 | grep -i 'ksh')
      version_output=$($SHELLSPEC_SHELL --version 2>&1 | head -1)
      major_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)
      minor_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f2)
      ;;
    zsh)
      shell_type=$($SHELLSPEC_SHELL --version | grep -i 'zsh')
      version_output=$($SHELLSPEC_SHELL --version | head -1)
      major_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)
      minor_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f2)
      ;;
    dash)
      shell_type=$($SHELLSPEC_SHELL --version 2>&1 | grep -i 'dash')
      version_output=$($SHELLSPEC_SHELL --version 2>&1 | head -1)
      major_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f1)
      minor_version=$(echo "$version_output" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d'.' -f2)
      ;;
    *)
      echo "Unsupported shell type: $expected_shell_type"
      return 1
      ;;
  esac

  echo "Expected shell type:$expected_shell_type, Detected shell type: $shell_type"
  echo "Expected shell major version:$expected_major_version, Detected major version: $major_version"
  echo "Expected shell minor version:$expected_minor_version, Detected minor version: $minor_version"

  if [ -z "$shell_type" ]; then
    echo "The shell specified by SHELLSPEC_SHELL is not $expected_shell_type."
    return 1
  fi

  if [ "$expected_major_version" -ne 0 ]; then
    if [ "$major_version" -lt "$expected_major_version" ]; then
      echo "The ${expected_shell_type} major version is lower than the expected version ${expected_major_version}."
      return 1
    fi

    if [ "$expected_minor_version" -ne 0 ]; then
      if [ "$minor_version" -lt "$expected_minor_version" ]; then
        echo "The ${expected_shell_type} minor version is lower than the expected version ${expected_minor_version}."
        return 1
      fi
      echo "${expected_shell_type} version ${major_version}.${minor_version} or higher is installed."
    else
      echo "${expected_shell_type} version ${major_version} or higher is installed."
    fi
  else
    echo "${expected_shell_type} is installed."
  fi

  return 0
}