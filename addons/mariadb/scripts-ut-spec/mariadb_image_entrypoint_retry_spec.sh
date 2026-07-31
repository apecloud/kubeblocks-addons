# shellcheck shell=sh

Describe "MariaDB image entrypoint fresh-init retry contract"
  Include ../scripts/mariadb-image-entrypoint.sh

  setup() {
    TEST_ROOT="$(mktemp -d)"
    export TEST_ROOT
  }

  cleanup() {
    rm -rf "${TEST_ROOT}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  make_late_ready_fixture() {
    fixture="$1"
    cat > "${fixture}" <<'FIXTURE'
#!/bin/bash
set -e
DATABASE_ALREADY_EXISTS=
DATADIR="${TEST_DATADIR:?}"
attempt_file="${TEST_ATTEMPT_FILE:?}"

docker_process_sql() {
  local attempts=0
  [ ! -f "${attempt_file}" ] || attempts="$(cat "${attempt_file}")"
  attempts=$((attempts + 1))
  printf '%s\n' "${attempts}" > "${attempt_file}"
  [ "${attempts}" -ge "${TEST_READY_AT:-33}" ]
}
sleep() { :; }
mysql_error() {
  printf '%s\n' "$*" >&2
  exit 1
}
docker_temp_server_start() {
  extraArgs=()
  local i
  for i in {30..0}; do
    if docker_process_sql "${extraArgs[@]}" --database=mysql <<<'SELECT 1' &>/dev/null; then
      break
    fi
    sleep 1
  done
  if [ "$i" = 0 ]; then
    mysql_error "Unable to start server."
  fi
}
docker_mariadb_init() {
  docker_temp_server_start
  touch "${DATADIR}/account-setup-committed"
}
_main() {
  docker_mariadb_init "$@"
}
_main "$@"
FIXTURE
    chmod 0555 "${fixture}"
  }

  run_unpatched_late_ready_fixture() {
    fixture="${TEST_ROOT}/docker-entrypoint.sh"
    make_late_ready_fixture "${fixture}"
    mkdir -p "${TEST_ROOT}/data"
    TEST_DATADIR="${TEST_ROOT}/data" \
      TEST_ATTEMPT_FILE="${TEST_ROOT}/attempts" \
      bash "${fixture}"
  }

  run_patched_late_ready_fixture() {
    fixture="${TEST_ROOT}/docker-entrypoint.sh"
    patched="${TEST_ROOT}/docker-entrypoint.patched.sh"
    make_late_ready_fixture "${fixture}"
    mkdir -p "${TEST_ROOT}/data"
    touch "${TEST_ROOT}/data/.kb-mariadb-image-init-in-progress"
    prepare_mariadb_image_entrypoint "${fixture}" "${patched}" 120
    TEST_DATADIR="${TEST_ROOT}/data" \
      TEST_ATTEMPT_FILE="${TEST_ROOT}/attempts" \
      bash "${patched}"
    attempts="$(cat "${TEST_ROOT}/attempts")"
    committed=false
    complete=false
    in_progress=true
    [ -f "${TEST_ROOT}/data/account-setup-committed" ] && committed=true
    [ -f "${TEST_ROOT}/data/.kb-mariadb-image-init-complete" ] && complete=true
    [ ! -f "${TEST_ROOT}/data/.kb-mariadb-image-init-in-progress" ] && in_progress=false
    printf 'attempts=%s committed=%s complete=%s in_progress=%s\n' \
      "${attempts}" "${committed}" "${complete}" "${in_progress}"
  }

  run_patched_after_budget_fixture() {
    fixture="${TEST_ROOT}/docker-entrypoint.sh"
    patched="${TEST_ROOT}/docker-entrypoint.patched.sh"
    make_late_ready_fixture "${fixture}"
    mkdir -p "${TEST_ROOT}/data"
    touch "${TEST_ROOT}/data/.kb-mariadb-image-init-in-progress"
    prepare_mariadb_image_entrypoint "${fixture}" "${patched}" 120
    rc=0
    TEST_READY_AT=121 \
      TEST_DATADIR="${TEST_ROOT}/data" \
      TEST_ATTEMPT_FILE="${TEST_ROOT}/attempts" \
      bash "${patched}" 2>"${TEST_ROOT}/stderr" || rc=$?
    attempts="$(cat "${TEST_ROOT}/attempts")"
    committed=false
    complete=false
    in_progress=false
    [ -f "${TEST_ROOT}/data/account-setup-committed" ] && committed=true
    [ -f "${TEST_ROOT}/data/.kb-mariadb-image-init-complete" ] && complete=true
    [ -f "${TEST_ROOT}/data/.kb-mariadb-image-init-in-progress" ] && in_progress=true
    error="$(tr '\n' ' ' < "${TEST_ROOT}/stderr")"
    printf 'rc=%s attempts=%s committed=%s complete=%s in_progress=%s error=%s\n' \
      "${rc}" "${attempts}" "${committed}" "${complete}" "${in_progress}" "${error}"
  }

  recover_partial_init() {
    data="${TEST_ROOT}/data"
    mkdir -p "${data}/mysql" "${data}/runtime-overrides.d" "${data}/log" "${data}/binlog" "${data}/tmp"
    touch "${data}/mysql/user.frm" "${data}/ibdata1"
    printf 'keep\n' > "${data}/runtime-overrides.cnf"
    printf 'evidence\n' > "${data}/log/entrypoint.log"
    touch "${data}/.kb-mariadb-image-init-in-progress"
    recover_partial_mariadb_image_init "${data}"
    mysql_absent=false
    ibdata_absent=false
    runtime_kept=false
    evidence_kept=false
    marker_absent=false
    [ ! -e "${data}/mysql" ] && mysql_absent=true
    [ ! -e "${data}/ibdata1" ] && ibdata_absent=true
    [ -f "${data}/runtime-overrides.cnf" ] && runtime_kept=true
    [ -f "${data}/log/entrypoint.log" ] && evidence_kept=true
    [ ! -e "${data}/.kb-mariadb-image-init-in-progress" ] && marker_absent=true
    printf 'mysql_absent=%s ibdata_absent=%s runtime_kept=%s evidence_kept=%s marker_absent=%s\n' \
      "${mysql_absent}" "${ibdata_absent}" "${runtime_kept}" "${evidence_kept}" "${marker_absent}"
  }

  preserve_legacy_existing_data() {
    data="${TEST_ROOT}/data"
    mkdir -p "${data}/mysql"
    printf 'legacy\n' > "${data}/mysql/user.frm"
    recover_partial_mariadb_image_init "${data}"
    cat "${data}/mysql/user.frm"
  }

  wrapper_is_mounted_and_called_before_existing_data_detection() {
    configmap="${SHELLSPEC_CWD:?}/addons/mariadb/templates/configmap-scripts-replication.yaml"
    entrypoint="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-entrypoint.sh"
    mount_count="$(grep -c 'mariadb-image-entrypoint.sh:' "${configmap}")"
    recover_line="$(grep -n '/scripts/mariadb-image-entrypoint.sh recover "${DATA_DIR}"' "${entrypoint}" | cut -d: -f1)"
    existing_line="$(grep -n '^HAS_EXISTING_DATA=false$' "${entrypoint}" | cut -d: -f1)"
    run_count="$(grep -c '/scripts/mariadb-image-entrypoint.sh run "${DATA_DIR}" mariadbd' "${entrypoint}")"
    printf 'mount=%s recover_before_existing=%s run=%s\n' \
      "${mount_count}" "$([ "${recover_line}" -lt "${existing_line}" ] && echo true || echo false)" "${run_count}"
  }

  It "reproduces the upstream 30-attempt boundary before the addon patch"
    When call run_unpatched_late_ready_fixture
    The status should be failure
    The stderr should include "Unable to start server."
  End

  It "admits a server that becomes ready on attempt 33 and commits account setup"
    When call run_patched_late_ready_fixture
    The status should be success
    The output should equal "attempts=33 committed=true complete=true in_progress=false"
  End

  It "fails closed after the 120-second budget without committing partial initialization"
    When call run_patched_after_budget_fixture
    The status should be success
    The output should equal "rc=1 attempts=121 committed=false complete=false in_progress=true error=Unable to start server. "
  End

  It "recovers only addon-owned interrupted fresh initialization while preserving config and evidence"
    When call recover_partial_init
    The status should be success
    The output should equal "mysql_absent=true ibdata_absent=true runtime_kept=true evidence_kept=true marker_absent=true"
    The stderr should include "recovering interrupted addon-owned MariaDB fresh initialization"
  End

  It "does not erase legacy existing data without the addon in-progress marker"
    When call preserve_legacy_existing_data
    The status should be success
    The output should equal "legacy"
  End

  It "mounts the wrapper, recovers before existing-data classification, and owns the image-entrypoint launch"
    When call wrapper_is_mounted_and_called_before_existing_data_detection
    The status should be success
    The output should equal "mount=1 recover_before_existing=true run=1"
  End

  It "rejects unsafe datadir recovery targets"
    When call recover_partial_mariadb_image_init "/"
    The status should be failure
    The stderr should include "unsafe MariaDB data directory"
  End

  It "rejects an unbounded temporary-server startup timeout"
    When call validate_temp_server_start_timeout "301"
    The status should be failure
    The stderr should include "between 31 and 300 seconds"
  End
End
