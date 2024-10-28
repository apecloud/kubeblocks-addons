# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Inject Bash Script Tests"
  Include ../scripts/inject-bash.sh

  init() {
    export ETCD_VERSION="3.4.22"
  }
  BeforeAll "init"

  cleanup() {
    unset ETCD_VERSION
  }
  AfterAll 'cleanup'

  Describe "inject_bash()"
    It "fails to inject bash when version is not provided"
      When call inject_bash ""
      The status should be failure
      The stderr should include "Invalid version format, check ETCD_VERSION"
    End

    It "injects bash successfully for valid version"
      When call inject_bash "$ETCD_VERSION"
      The status should be success
      The stdout should include "No need to inject bash for etcd-$ETCD_VERSION image"
    End

    It "fails to inject bash for invalid version format"
      When call inject_bash "invalid_version"
      The status should be failure
      The stderr should include "Invalid version format, check ETCD_VERSION"
    End

    # inject action will not be performed in shellspec
  End
End