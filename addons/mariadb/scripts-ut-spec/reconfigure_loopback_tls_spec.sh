# shellcheck shell=sh

# r25: execute the complete Helm-rendered reconfigure action command instead
# of extracting a helper fragment.  The only harness rewrite redirects the
# persisted variant's absolute data paths into an isolated temporary directory;
# argv parsing, SQL construction, error classification, and write ordering stay
# byte-for-byte from the rendered production command.

Describe "MariaDB reconfigure loopback TLS mode"
  ADDON_ROOT="${SHELLSPEC_CWD:?}/addons/mariadb"
  CHART_PATH="${ADDON_ROOT}"
  HELPERS_TPL="${ADDON_ROOT}/templates/_helpers.tpl"

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  ruby_not_available() { ! command -v ruby >/dev/null 2>&1; }
  Skip if "helm is unavailable" helm_not_available
  Skip if "ruby is unavailable" ruby_not_available

  cleanup_case_dir() {
    [ -n "${CASE_DIR:-}" ] && rm -rf "${CASE_DIR}" 2>/dev/null || true
  }

  AfterEach 'cleanup_case_dir'

  extract_rendered_action() {
    rendered="$1"
    config_name="$2"
    destination="$3"
    ruby -ryaml -e '
      rendered, config_name, destination = ARGV
      hits = []
      YAML.load_stream(File.read(rendered)).compact.each do |doc|
        next unless doc["kind"] == "ComponentDefinition"
        (doc.dig("spec", "configs") || []).each do |config|
          next unless config["name"] == config_name
          hits << [doc.dig("metadata", "name"), config.dig("reconfigure", "exec", "command")]
        end
      end
      abort "expected one rendered action for #{config_name}, got #{hits.length}" unless hits.length == 1
      component_name, command = hits.first
      expected = ["/bin/sh", "-c", String, "reconfigure"]
      abort "unexpected command shape for #{config_name}: #{command.inspect}" unless
        command.is_a?(Array) && command.length == 4 &&
        command[0] == expected[0] && command[1] == expected[1] &&
        command[2].is_a?(expected[2]) && command[3] == expected[3]
      File.write(destination, command[2])
    ' "${rendered}" "${config_name}" "${destination}"
  }

  write_fake_client() {
    destination="$1"
    cat >"${destination}" <<'FAKECLIENT'
#!/bin/sh
set -eu

: "${FAKE_CLIENT_LOG:?}"
printf 'ARGV' >>"${FAKE_CLIENT_LOG}"
for arg in "$@"; do
  printf '\t%s' "${arg}" >>"${FAKE_CLIENT_LOG}"
done
printf '\n' >>"${FAKE_CLIENT_LOG}"

skip_ssl=false
query=''
for arg in "$@"; do
  [ "${arg}" = "--skip-ssl" ] && skip_ssl=true
  query="${arg}"
done

if [ "${FAKE_FORCE_RC1:-false}" = "true" ]; then
  echo "ERROR 2002 (HY000): forced client failure" >&2
  exit 1
fi

if [ "${TLS_ENABLED:-false}" != "true" ] && [ "${skip_ssl}" != "true" ]; then
  echo "ERROR 2026 (HY000): TLS/SSL error: SSL is required, but the server does not support it" >&2
  exit 1
fi

expected='SET GLOBAL `long_query_time` = 5;'
if [ "${query}" != "${expected}" ]; then
  echo "unexpected SQL: ${query}" >&2
  exit 64
fi
printf 'SQL\t%s\n' "${query}" >>"${FAKE_CLIENT_LOG}"
FAKECLIENT
    chmod +x "${destination}"
  }

  prepare_rendered_action() {
    config_name="$1"
    CASE_DIR="$(mktemp -d)"
    mkdir -p "${CASE_DIR}/bin"
    helm template r25-loopback-tls "${CHART_PATH}" >"${CASE_DIR}/rendered.yaml"
    extract_rendered_action \
      "${CASE_DIR}/rendered.yaml" \
      "${config_name}" \
      "${CASE_DIR}/action.sh" || return 1
    write_fake_client "${CASE_DIR}/bin/mariadb"

    if [ "${config_name}" = "mariadb-replication-config" ]; then
      overrides_dir="${CASE_DIR}/data/runtime-overrides.d"
      loader_file="${CASE_DIR}/data/runtime-overrides.cnf"
      mkdir -p "${CASE_DIR}/data"
      sed \
        -e "s#/var/lib/mysql/runtime-overrides.d#${overrides_dir}#g" \
        -e "s#/var/lib/mysql/runtime-overrides.cnf#${loader_file}#g" \
        "${CASE_DIR}/action.sh" >"${CASE_DIR}/action.sandbox.sh"
      mv "${CASE_DIR}/action.sandbox.sh" "${CASE_DIR}/action.sh"
    fi
  }

  invoke_action() {
    tls_enabled="$1"
    force_rc1="$2"
    PATH="${CASE_DIR}/bin:${PATH}" \
      FAKE_CLIENT_LOG="${CASE_DIR}/client.log" \
      FAKE_FORCE_RC1="${force_rc1}" \
      TLS_ENABLED="${tls_enabled}" \
      MARIADB_ROOT_PASSWORD="test-only" \
      MARIADB_INTERNAL_ROOT_USER="kb_internal_root" \
      /bin/sh -c "$(cat "${CASE_DIR}/action.sh")" \
      reconfigure long_query_time 5
  }

  assert_success_contract() {
    config_name="$1"
    tls_enabled="$2"
    expected_skip_ssl="$3"
    prepare_rendered_action "${config_name}" || return 1

    action_output="$(invoke_action "${tls_enabled}" false 2>&1)"
    action_rc=$?
    printf '%s\n' "${action_output}"
    [ "${action_rc}" -eq 0 ] || return "${action_rc}"

    [ "$(grep -c '^ARGV' "${CASE_DIR}/client.log")" -eq 1 ] || return 1
    [ "$(grep -c '^SQL' "${CASE_DIR}/client.log")" -eq 1 ] || return 1
    tab="$(printf '\t')"
    grep -Fq "SQL${tab}SET GLOBAL \`long_query_time\` = 5;" "${CASE_DIR}/client.log" || return 1
    ! grep -Fq 'SELECT ' "${CASE_DIR}/client.log" || return 1
    grep -Fq -- '--user=kb_internal_root' "${CASE_DIR}/client.log" || return 1
    grep -Fq -- '--host=127.0.0.1' "${CASE_DIR}/client.log" || return 1
    grep -Fq "${tab}-P${tab}3306${tab}" "${CASE_DIR}/client.log" || return 1

    if [ "${expected_skip_ssl}" = "true" ]; then
      grep -Fq "${tab}--skip-ssl${tab}" "${CASE_DIR}/client.log" || return 1
    else
      ! grep -Fq -- '--skip-ssl' "${CASE_DIR}/client.log" || return 1
    fi

    if [ "${config_name}" = "mariadb-replication-config" ]; then
      override="${CASE_DIR}/data/runtime-overrides.d/long_query_time.cnf"
      [ -f "${override}" ] || return 1
      grep -Fxq '[mysqld]' "${override}" || return 1
      grep -Fxq 'long_query_time = 5' "${override}" || return 1
    fi
  }

  assert_persisted_failure_before_write() {
    prepare_rendered_action "mariadb-replication-config" || return 1
    action_rc=0
    action_output="$(invoke_action "" true 2>&1)" || action_rc=$?
    printf '%s\n' "${action_output}"
    [ "${action_rc}" -ne 0 ] || return 1
    printf '%s' "${action_output}" | grep -Fq 'forced client failure' || return 1
    [ ! -e "${CASE_DIR}/data/runtime-overrides.d/long_query_time.cnf" ] || return 1
    [ "$(grep -c '^ARGV' "${CASE_DIR}/client.log")" -eq 1 ] || return 1
    [ "$(grep -c '^SQL' "${CASE_DIR}/client.log" 2>/dev/null || true)" -eq 0 ] || return 1
  }

  rendered_flag_contract() {
    CASE_DIR="$(mktemp -d)"
    helm template r25-loopback-tls "${CHART_PATH}" >"${CASE_DIR}/rendered.yaml"

    total=0
    for config_name in \
      mariadb-standalone-config \
      mariadb-galera-config \
      mariadb-replication-config
    do
      action_file="${CASE_DIR}/${config_name}.sh"
      extract_rendered_action "${CASE_DIR}/rendered.yaml" "${config_name}" "${action_file}" || return 1
      count="$(grep -c -- '--skip-ssl' "${action_file}" || true)"
      [ "${count}" -eq 1 ] || {
        echo "${config_name}: expected one --skip-ssl, got ${count}" >&2
        return 1
      }
      total=$((total + count))
    done
    [ "${total}" -eq 3 ] || return 1
    printf 'rendered-actions=3 rendered-flags=%s\n' "${total}"
  }

  source_flag_contract() {
    wrapper_count="$(grep -c '^[[:space:]]*mariadb_exec() {' "${HELPERS_TPL}")"
    flag_count="$(grep -c -- '--skip-ssl' "${HELPERS_TPL}" || true)"
    [ "${wrapper_count}" -eq 2 ] || return 1
    [ "${flag_count}" -eq 2 ] || return 1
    printf 'source-wrappers=%s source-flags=%s\n' "${wrapper_count}" "${flag_count}"
  }

  static_version_band_contract() {
    CASE_DIR="$(mktemp -d)"
    helm template r25-loopback-tls "${CHART_PATH}" >"${CASE_DIR}/rendered.yaml"
    ruby -ryaml -e '
      rendered = ARGV.fetch(0)
      required = %w[10.6.15 11.4.10 12.0.2]
      component_version = YAML.load_stream(File.read(rendered)).compact.find do |doc|
        doc["kind"] == "ComponentVersion" && doc.dig("metadata", "name") == "mariadb"
      end
      abort "rendered mariadb ComponentVersion is missing" unless component_version
      actual = (component_version.dig("spec", "releases") || []).map { |release| release["serviceVersion"] }
      missing = required - actual
      abort "missing representative serviceVersion bands: #{missing.join(",")}" unless missing.empty?
      puts "static-version-bands=#{required.join(",")}"
    ' "${CASE_DIR}/rendered.yaml"
  }

  It "old RED/new GREEN: standalone rendered argv applies the single SET over explicit TLS-off loopback"
    When call assert_success_contract "mariadb-standalone-config" "false" "true"
    The status should be success
    The output should include "Set parameter long_query_time to value 5"
  End

  It "old RED/new GREEN: Galera rendered argv applies the single SET when TLS is undeclared"
    When call assert_success_contract "mariadb-galera-config" "" "true"
    The status should be success
    The output should include "Set parameter long_query_time to value 5"
  End

  It "old RED/new GREEN: replication rendered argv writes the override only after SET succeeds"
    When call assert_success_contract "mariadb-replication-config" "" "true"
    The status should be success
    The output should include "Set parameter long_query_time to value 5"
  End

  It "keeps TLS-enabled standalone on the existing client behavior without --skip-ssl"
    When call assert_success_contract "mariadb-standalone-config" "true" "false"
    The status should be success
    The output should include "Set parameter long_query_time to value 5"
  End

  It "fails persisted reconfigure before writing an override when the client returns rc1"
    When call assert_persisted_failure_before_write
    The status should be success
    The output should include "forced client failure"
  End

  It "keeps exactly two source wrappers and two source flag sites"
    When call source_flag_contract
    The status should be success
    The output should equal "source-wrappers=2 source-flags=2"
  End

  It "renders exactly one flag in each of the three final actions"
    When call rendered_flag_contract
    The status should be success
    The output should equal "rendered-actions=3 rendered-flags=3"
  End

  It "keeps the same rendered action contract across representative 10.6, 11.4, and 12.0 releases"
    When call static_version_band_contract
    The status should be success
    The output should equal "static-version-bands=10.6.15,11.4.10,12.0.2"
  End
End
