# shellcheck shell=sh

Describe "RustFS roleProbe render contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  prepare_chart() {
    tmp_dir=$(mktemp -d -t rustfs-roleprobe-render-XXXXXX) || return $?
    mkdir -p "${tmp_dir}/addons" || return $?
    cp -R "$(repo_root)/addons/rustfs" "${tmp_dir}/addons/rustfs" || return $?
    cp -R "$(repo_root)/addons/kblib" "${tmp_dir}/addons/kblib" || return $?
  }

  render_cmpd() {
    prepare_chart || return $?
    helm template test "${tmp_dir}/addons/rustfs" \
      --dependency-update \
      --show-only templates/cmpd.yaml
  }

  validate_roleprobe_cadence() {
    render_cmpd | ruby -ryaml -e '
      document = YAML.load_stream($stdin.read).compact.find do |item|
        item.is_a?(Hash) && item["kind"] == "ComponentDefinition"
      end
      abort "ComponentDefinition is missing" unless document
      probe = document.dig("spec", "lifecycleActions", "roleProbe")
      abort "roleProbe is missing" unless probe.is_a?(Hash)
      abort "periodSeconds must be 1, got #{probe["periodSeconds"].inspect}" unless probe["periodSeconds"] == 1
      abort "timeoutSeconds must be 3, got #{probe["timeoutSeconds"].inspect}" unless probe["timeoutSeconds"] == 3
      puts "RustFS roleProbe cadence is 1s/3s"
    '
  }

  validate_roleprobe_command_hash() {
    render_cmpd | ruby -ryaml -rdigest -e '
      document = YAML.load_stream($stdin.read).compact.find do |item|
        item.is_a?(Hash) && item["kind"] == "ComponentDefinition"
      end
      command = document.dig("spec", "lifecycleActions", "roleProbe", "exec", "command")
      actual = Digest::SHA256.hexdigest(YAML.dump(command))
      expected = "01fa10f938f541513fa73a58552b65e6a3ded71efc3b2cd6f40815781907e10e"
      abort "roleProbe exec command changed: #{actual}" unless actual == expected
      puts "RustFS roleProbe exec command hash is unchanged"
    '
  }

  prepare_probe_stubs() {
    stub_dir="${tmp_dir}/stubs"
    call_log="${tmp_dir}/calls.log"
    mkdir -p "$stub_dir" || return $?
    : >"$call_log" || return $?

    printf '%s\n' \
      '#!/bin/sh' \
      'printf "wget\\n" >>"$CALL_LOG"' \
      'case "$WGET_MODE" in' \
      '  success) exit 0 ;;' \
      '  fail) exit 1 ;;' \
      '  hang) sleep 10; exit 1 ;;' \
      '  *) exit 2 ;;' \
      'esac' >"${stub_dir}/wget" || return $?
    chmod +x "${stub_dir}/wget" || return $?

    printf '%s\n' \
      '#!/bin/sh' \
      'printf "curl\\n" >>"$CALL_LOG"' \
      'case "$CURL_MODE" in' \
      '  success) exit 0 ;;' \
      '  fail) exit 1 ;;' \
      '  *) exit 2 ;;' \
      'esac' >"${stub_dir}/curl" || return $?
    chmod +x "${stub_dir}/curl" || return $?
  }

  extract_probe_script() {
    render_cmpd | ruby -ryaml -e '
      document = YAML.load_stream($stdin.read).compact.find do |item|
        item.is_a?(Hash) && item["kind"] == "ComponentDefinition"
      end
      puts document.dig("spec", "lifecycleActions", "roleProbe", "exec", "command").fetch(2)
    '
  }

  run_probe_case() {
    wget_mode="$1"
    curl_mode="$2"
    budget="${3:-0}"
    prepare_chart || return $?
    probe_script=$(extract_probe_script) || return $?
    prepare_probe_stubs || return $?

    if [ "$budget" -gt 0 ]; then
      role=$(timeout "$budget" /usr/bin/env -i PATH="${stub_dir}:$PATH" CALL_LOG="$call_log" \
        WGET_MODE="$wget_mode" CURL_MODE="$curl_mode" TLS_ENABLED=false "$SHELLSPEC_SHELL" -c "$probe_script")
      rc=$?
    else
      role=$(/usr/bin/env -i PATH="${stub_dir}:$PATH" CALL_LOG="$call_log" \
        WGET_MODE="$wget_mode" CURL_MODE="$curl_mode" TLS_ENABLED=false "$SHELLSPEC_SHELL" -c "$probe_script")
      rc=$?
    fi

    printf 'ROLE=%s\n' "$role"
    printf 'CALLS='
    tr '\n' ',' <"$call_log"
    printf '\n'
    return "$rc"
  }

  cleanup_chart() {
    [ -n "${tmp_dir:-}" ] && rm -rf "${tmp_dir}" 2>/dev/null || true
    tmp_dir=""
  }
  AfterEach 'cleanup_chart'

  It "renders a one-second period and three-second timeout"
    When call validate_roleprobe_cadence
    The status should be success
    The output should include "RustFS roleProbe cadence is 1s/3s"
  End

  It "keeps the pre-change exec command structure byte-for-byte canonical"
    When call validate_roleprobe_command_hash
    The status should be success
    The output should include "RustFS roleProbe exec command hash is unchanged"
  End

  It "reports readwrite when wget succeeds without calling curl"
    When call run_probe_case success fail
    The status should be success
    The output should include "ROLE=readwrite"
    The output should include "CALLS=wget,"
    The output should not include "curl,"
  End

  It "falls back to curl after a fast wget failure"
    When call run_probe_case fail success
    The status should be success
    The output should include "ROLE=readwrite"
    The output should include "CALLS=wget,curl,"
  End

  It "reports notready when both clients fail"
    When call run_probe_case fail fail
    The status should be success
    The output should include "ROLE=notready"
    The output should include "CALLS=wget,curl,"
  End

  It "emits no role token when a hanging wget consumes the action budget"
    When call run_probe_case hang success 3
    The status should equal 124
    The output should include "ROLE="
    The output should not include "ROLE=readwrite"
    The output should not include "ROLE=notready"
    The output should include "CALLS=wget,"
    The output should not include "curl,"
  End
End
