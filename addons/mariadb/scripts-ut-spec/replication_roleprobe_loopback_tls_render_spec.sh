# shellcheck shell=sh

# r25: exercise the exact roleProbe command and script carried by the rendered
# ConfigMap/ComponentDefinition.  The harness changes only the absolute
# /scripts mount path to an isolated extracted script; command shape, argv,
# fallback order, role output, and repair control flow remain production code.

Describe "MariaDB replication roleProbe loopback TLS mode"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  CHART_PATH="${ADDON_ROOT}"

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  ruby_not_available() { ! command -v ruby >/dev/null 2>&1; }
  Skip if "helm is unavailable" helm_not_available
  Skip if "ruby is unavailable" ruby_not_available

  cleanup_case_dir() {
    [ -n "${CASE_DIR:-}" ] && rm -rf "${CASE_DIR}" 2>/dev/null || true
  }
  AfterEach 'cleanup_case_dir'

  extract_rendered_contract() {
    rendered="$1"
    script_destination="$2"
    command_destination="$3"
    ruby -ryaml -e '
      rendered, script_destination, command_destination = ARGV
      docs = YAML.load_stream(File.read(rendered)).compact

      scripts = []
      docs.each do |doc|
        next unless doc["kind"] == "ConfigMap"
        value = doc.dig("data", "replication-roleprobe.sh")
        scripts << [doc.dig("metadata", "name"), value] if value
      end
      abort "expected one rendered replication-roleprobe.sh, got #{scripts.length}" unless scripts.length == 1

      probes = []
      docs.each do |doc|
        next unless doc["kind"] == "ComponentDefinition"
        command = doc.dig("spec", "lifecycleActions", "roleProbe", "exec", "command")
        probes << [doc.dig("metadata", "name"), command] if command
      end
      probes.select! { |name, _| name.include?("replication") }
      abort "expected one rendered replication roleProbe, got #{probes.length}" unless probes.length == 1
      command = probes.first.last
      expected = ["/bin/sh", "-c", "MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY=true /scripts/replication-roleprobe.sh"]
      abort "unexpected roleProbe command: #{command.inspect}" unless command == expected

      File.write(script_destination, scripts.first.last)
      File.write(command_destination, command.fetch(2))
    ' "${rendered}" "${script_destination}" "${command_destination}"
  }

  write_fake_clients() {
    mkdir -p "${CASE_DIR}/bin" "${CASE_DIR}/mysql-client/bin"
    cat >"${CASE_DIR}/bin/mariadb" <<'FAKECLIENT'
#!/bin/sh
set -eu

: "${FAKE_CLIENT_LOG:?}"
printf 'ARGV' >>"${FAKE_CLIENT_LOG}"
for arg in "$@"; do
  printf '\t%s' "${arg}" >>"${FAKE_CLIENT_LOG}"
done
printf '\n' >>"${FAKE_CLIENT_LOG}"

skip_ssl_count=0
user=''
for arg in "$@"; do
  [ "${arg}" = "--skip-ssl" ] && skip_ssl_count=$((skip_ssl_count + 1))
  case "${arg}" in
    -u*) user="${arg#-u}" ;;
  esac
done
if [ "${skip_ssl_count}" -ne 1 ]; then
  echo "ERROR 2026 (HY000): TLS/SSL error: SSL is required, but the server does not support it" >&2
  exit 1
fi

case "$*" in
  *"SELECT 1"*)
    printf '1\n'
    ;;
  *"SHOW VARIABLES LIKE 'bind_address'"*)
    printf 'bind_address\t0.0.0.0\n'
    ;;
  *"SELECT UPPER(CAST(@@global.read_only AS CHAR));"*)
    printf '0\n'
    ;;
  *"SHOW SLAVE STATUS\\G"*)
    [ "${user}" != "root" ] || exit 1
    if [ "${FAKE_REPAIR_MODE:-false}" = "true" ] && [ ! -f "${FAKE_REPAIRED_FILE}" ]; then
      cat <<'STATUS'
Slave_IO_Running: Yes
Slave_SQL_Running: No
Last_IO_Errno: 0
Last_SQL_Errno: 1062
Last_SQL_Error: duplicate row in kubeblocks.kb_health_check
STATUS
    else
      cat <<'STATUS'
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Last_IO_Errno: 0
Last_SQL_Errno: 0
STATUS
    fi
    ;;
  *"START SLAVE SQL_THREAD;"*)
    : >"${FAKE_REPAIRED_FILE}"
    ;;
esac
FAKECLIENT
    chmod +x "${CASE_DIR}/bin/mariadb"

    cat >"${CASE_DIR}/mysql-client/bin/mariadb" <<'LOWERCLIENT'
#!/bin/sh
echo lower-priority-client-must-not-run >&2
exit 99
LOWERCLIENT
    chmod +x "${CASE_DIR}/mysql-client/bin/mariadb"
  }

  prepare_rendered_probe() {
    CASE_DIR="$(mktemp -d)"
    mkdir -p "${CASE_DIR}/data"
    helm template r25-roleprobe-loopback-tls "${CHART_PATH}" >"${CASE_DIR}/rendered.yaml" || return 1
    extract_rendered_contract \
      "${CASE_DIR}/rendered.yaml" \
      "${CASE_DIR}/replication-roleprobe.sh" \
      "${CASE_DIR}/command.txt" || return 1
    chmod +x "${CASE_DIR}/replication-roleprobe.sh"
    sed "s#/scripts/replication-roleprobe.sh#${CASE_DIR}/replication-roleprobe.sh#g" \
      "${CASE_DIR}/command.txt" >"${CASE_DIR}/sandbox-command.txt"
    write_fake_clients
    : >"${CASE_DIR}/data/.replication-ready"
    : >"${CASE_DIR}/data/.sql-listener-ready"
    : >"${CASE_DIR}/data/.primary-read-write-ready"
  }

  invoke_rendered_probe() {
    repair_mode="$1"
    PATH="${CASE_DIR}/bin:${PATH}" \
      MYSQL_CLIENT_DIR="${CASE_DIR}/mysql-client" \
      MARIADB_DATADIR="${CASE_DIR}/data" \
      MARIADB_ROOT_HOST="localhost" \
      MARIADB_ROOT_USER="root" \
      MARIADB_INTERNAL_ROOT_USER="kb_internal_root" \
      MARIADB_ROOT_PASSWORD="test-only" \
      MARIADB_REPLICATION_MODE="async" \
      FAKE_CLIENT_LOG="${CASE_DIR}/client.log" \
      FAKE_REPAIR_MODE="${repair_mode}" \
      FAKE_REPAIRED_FILE="${CASE_DIR}/repaired" \
      /bin/sh -c "$(cat "${CASE_DIR}/sandbox-command.txt")"
  }

  assert_every_client_call_has_one_skip_ssl() {
    awk -F '\t' '
      BEGIN { calls = 0; bad = 0 }
      /^ARGV/ {
        calls++
        count = 0
        for (i = 2; i <= NF; i++) if ($i == "--skip-ssl") count++
        if (count != 1) bad = 1
      }
      END { exit(calls > 0 && bad == 0 ? 0 : 1) }
    ' "${CASE_DIR}/client.log"
  }

  primary_production_contract() {
    prepare_rendered_probe || return 1
    role="$(invoke_rendered_probe false 2>"${CASE_DIR}/stderr")"
    rc=$?
    [ "${rc}" -eq 0 ] || {
      cat "${CASE_DIR}/stderr" >&2
      return "${rc}"
    }
    [ "${role}" = "primary" ] || return 1
    assert_every_client_call_has_one_skip_ssl || return 1
    [ "$(grep -c '^ARGV' "${CASE_DIR}/client.log")" -eq 3 ] || return 1
    printf '%s\n' "${role}"
  }

  secondary_fallback_contract() {
    prepare_rendered_probe || return 1
    : >"${CASE_DIR}/data/master.info"
    role="$(invoke_rendered_probe false 2>"${CASE_DIR}/stderr")"
    rc=$?
    [ "${rc}" -eq 0 ] || {
      cat "${CASE_DIR}/stderr" >&2
      return "${rc}"
    }
    [ "${role}" = "secondary" ] || return 1
    assert_every_client_call_has_one_skip_ssl || return 1
    grep -Fq -- '-uroot' "${CASE_DIR}/client.log" || return 1
    grep -Fq -- '-ukb_internal_root' "${CASE_DIR}/client.log" || return 1
    grep -Fq 'SHOW SLAVE STATUS\G' "${CASE_DIR}/client.log" || return 1
    printf '%s\n' "${role}"
  }

  secondary_repair_contract() {
    prepare_rendered_probe || return 1
    : >"${CASE_DIR}/data/master.info"
    role="$(invoke_rendered_probe true 2>"${CASE_DIR}/stderr")"
    rc=$?
    [ "${rc}" -eq 0 ] || {
      cat "${CASE_DIR}/stderr" >&2
      return "${rc}"
    }
    [ "${role}" = "secondary" ] || return 1
    [ -f "${CASE_DIR}/repaired" ] || return 1
    assert_every_client_call_has_one_skip_ssl || return 1
    grep -Fq 'STOP SLAVE SQL_THREAD;' "${CASE_DIR}/client.log" || return 1
    grep -Fq 'DELETE FROM kubeblocks.kb_health_check;' "${CASE_DIR}/client.log" || return 1
    grep -Fq 'START SLAVE SQL_THREAD;' "${CASE_DIR}/client.log" || return 1
    printf '%s\n' "${role}"
  }

  It "old RED/new GREEN: rendered production primary publishes through TLS-off loopback"
    When call primary_production_contract
    The status should be success
    The output should equal "primary"
  End

  It "keeps labeled SHOW SLAVE STATUS root-to-internal fallback on the rendered secondary path"
    When call secondary_fallback_contract
    The status should be success
    The output should equal "secondary"
  End

  It "routes rendered secondary STOP/repair/START through the same TLS-off wrapper"
    When call secondary_repair_contract
    The status should be success
    The output should equal "secondary"
  End
End
