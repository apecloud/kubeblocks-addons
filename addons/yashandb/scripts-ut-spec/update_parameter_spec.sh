# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "update_parameter_spec.sh skip cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

# Contract (KB main/1.2+): the reconfigure exec receives exactly one changed
# key/value pair from ActionRequest.Arguments as "$1"/"$2". Unknown keys and
# missing arguments must fail closed (rc!=0) -- a skip-with-rc0 lets a
# mistyped or contract-drifted parameter report success while applying
# nothing. Applying the same pair twice must be idempotent and touch only the
# target key.
Describe "update-parameter.sh"
  setup_param() {
    PARAM_TEST_DIR=$(mktemp -d -t yashandb-param-XXXXXX)
    export YASDB_MOUNT_HOME="${PARAM_TEST_DIR}"
    export YASDB_DATA="${PARAM_TEST_DIR}/data"
    mkdir -p "${YASDB_DATA}/config"
    printf 'YASDB_DATA=%s\n' "${YASDB_DATA}" >"${PARAM_TEST_DIR}/.temp.ini"
    printf '%s\n' "OPEN_CURSORS=310" "MAX_SESSIONS=1024" >"${PARAM_TEST_DIR}/install.ini"
    printf '%s\n' "OPEN_CURSORS=310" "MAX_SESSIONS=1024" >"${YASDB_DATA}/config/yasdb.ini"
  }
  cleanup_param() {
    rm -rf "${PARAM_TEST_DIR}"
    unset YASDB_MOUNT_HOME YASDB_DATA
  }
  BeforeEach "setup_param"
  AfterEach "cleanup_param"

  It "fails closed when invoked without arguments"
    When run bash ../scripts/update-parameter.sh
    The status should be failure
    The stderr should be present
  End

  It "fails closed when the value argument is missing"
    When run bash ../scripts/update-parameter.sh OPEN_CURSORS
    The status should be failure
    The stderr should be present
  End

  It "fails closed on an unknown parameter instead of skipping with rc=0"
    When run bash ../scripts/update-parameter.sh NOT_A_YASDB_PARAMETER 42
    The status should be failure
    The stderr should include "unsupported YashanDB parameter"
  End

  It "updates only the target key in both persisted files"
    When run bash ../scripts/update-parameter.sh OPEN_CURSORS 500
    The status should be success
    The output should include "updated YashanDB parameter OPEN_CURSORS"
    The contents of file "${PARAM_TEST_DIR}/install.ini" should include "OPEN_CURSORS=500"
    The contents of file "${PARAM_TEST_DIR}/install.ini" should include "MAX_SESSIONS=1024"
    The contents of file "${YASDB_DATA}/config/yasdb.ini" should include "OPEN_CURSORS=500"
    The contents of file "${YASDB_DATA}/config/yasdb.ini" should include "MAX_SESSIONS=1024"
  End

  It "is idempotent when applying the same pair twice"
    bash ../scripts/update-parameter.sh OPEN_CURSORS 500 >/dev/null
    bash ../scripts/update-parameter.sh OPEN_CURSORS 500 >/dev/null
    # exactly one OPEN_CURSORS line remains in each file, with the target value
    When run bash -c 'printf "%s %s" "$(grep -c "^OPEN_CURSORS=" "$1")" "$(grep -c "^OPEN_CURSORS=" "$2")"' _ "${PARAM_TEST_DIR}/install.ini" "${YASDB_DATA}/config/yasdb.ini"
    The status should be success
    The output should eq "1 1"
    The contents of file "${PARAM_TEST_DIR}/install.ini" should include "OPEN_CURSORS=500"
  End
End
