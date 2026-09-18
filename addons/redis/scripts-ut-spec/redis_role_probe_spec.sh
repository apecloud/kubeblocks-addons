# shellcheck shell=bash

if ! validate_shell_type_and_version "bash" 3 &>/dev/null; then
  echo "redis_role_probe_spec.sh skips all cases because bash 3 or higher is not installed."
  exit 0
fi

Describe 'redis-role-probe.sh'
  probe_script='../scripts/redis-role-probe.sh'
  fixture_dir="${SHELLSPEC_TMPBASE}/redis-role-probe"
  dbctl_fixture="${fixture_dir}/dbctl"

  setup() {
    mkdir -p "${fixture_dir}"
    cat >"${dbctl_fixture}" <<'MOCK'
#!/bin/bash
printf '%s\n' "${DBCTL_ROLE:-primary}"
exit "${DBCTL_RC:-0}"
MOCK
    chmod +x "${dbctl_fixture}"
  }
  BeforeEach 'setup'

  It 'publishes primary as a single role token'
    export DBCTL_ROLE=primary
    unset DBCTL_RC
    When run bash "${probe_script}" "${dbctl_fixture}"
    The status should be success
    The output should eq 'primary'
    The stderr should be blank
  End

  It 'publishes secondary as a single role token'
    export DBCTL_ROLE=secondary
    unset DBCTL_RC
    When run bash "${probe_script}" "${dbctl_fixture}"
    The status should be success
    The output should eq 'secondary'
    The stderr should be blank
  End

  It 'rejects JSON output instead of publishing an invalid role event'
    export DBCTL_ROLE='{"term":"1","PodRoleNamePairs":[]}'
    unset DBCTL_RC
    When run bash "${probe_script}" "${dbctl_fixture}"
    The status should be failure
    The output should be blank
    The stderr should include 'unexpected Redis role'
  End

  It 'rejects an unknown role instead of creating an undeclared role label'
    export DBCTL_ROLE=unknown
    unset DBCTL_RC
    When run bash "${probe_script}" "${dbctl_fixture}"
    The status should be failure
    The output should be blank
    The stderr should include 'unexpected Redis role'
  End

  It 'propagates dbctl failure without publishing a role'
    export DBCTL_ROLE=''
    export DBCTL_RC=23
    When run bash "${probe_script}" "${dbctl_fixture}"
    The status should eq 23
    The output should be blank
  End
End
