# shellcheck shell=sh

Describe "reloader/update-parameter.sh"

  script_path() {
    printf "%s" "../reloader/update-parameter.sh"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-reloader-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CURL_LOG="${tmpdir}/curl.log"
    : > "${CURL_LOG}"
    export PATH CURL_LOG
    unset CURL_EXIT PATCH_BODY PATCH_CODE RELOAD_BODY RELOAD_CODE RESTART_BODY RESTART_CODE 2>/dev/null || true
    write_curl_stub
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  # The stub emulates `curl -s -m 30 -w "\n%{http_code}" ...`: it prints the
  # canned response body, a newline, then the canned HTTP status code, and
  # records every invocation so tests can assert which endpoints were called.
  write_curl_stub() {
    cat > "${bindir}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "${CURL_LOG}"
if [ -n "${CURL_EXIT:-}" ]; then
  exit "${CURL_EXIT}"
fi
url=""
for arg; do url="$arg"; done
case "$url" in
  */config)  printf '%s\n%s' "${PATCH_BODY:-}"   "${PATCH_CODE:-200}" ;;
  */reload)  printf '%s\n%s' "${RELOAD_BODY:-}"  "${RELOAD_CODE:-202}" ;;
  */restart) printf '%s\n%s' "${RESTART_BODY:-}" "${RESTART_CODE:-200}" ;;
  *)         printf '%s\n%s' "" "404" ;;
esac
EOF
    chmod +x "${bindir}/curl"
  }

  curl_log() {
    cat "${CURL_LOG}"
  }

  Describe "parameter routing"
    It "routes a PostgreSQL GUC into postgresql.parameters and reloads"
      When run sh "$(script_path)" "work_mem" "64MB"
      The status should eq 0
      The result of function curl_log should include '-X PATCH'
      The result of function curl_log should include 'http://localhost:8008/config'
      The result of function curl_log should include '"postgresql"'
      The result of function curl_log should include '"work_mem": "64MB"'
      The result of function curl_log should include 'http://localhost:8008/reload'
    End

    It "routes a patroni DCS parameter at top level and reloads"
      When run sh "$(script_path)" "loop_wait" "10"
      The status should eq 0
      The result of function curl_log should include '"loop_wait": "10"'
      The result of function curl_log should not include '"postgresql"'
      The result of function curl_log should include 'http://localhost:8008/reload'
    End

    It "restarts instead of reloading for a restart-class parameter"
      When run sh "$(script_path)" "shared_buffers" "2GB"
      The status should eq 0
      The result of function curl_log should include '"shared_buffers": "2GB"'
      The result of function curl_log should include 'http://localhost:8008/restart'
      The result of function curl_log should not include 'http://localhost:8008/reload'
    End
  End

  Describe "patroni API error propagation"
    It "fails and skips reload when patroni rejects the config PATCH"
      export PATCH_CODE=400
      export PATCH_BODY='{"error":"invalid parameter"}'
      When run sh "$(script_path)" "work_mem" "nonsense"
      The status should be failure
      The error should include "HTTP 400"
      The output should include "invalid parameter"
      The result of function curl_log should not include 'http://localhost:8008/reload'
      The result of function curl_log should not include 'http://localhost:8008/restart'
    End

    It "fails when patroni is unreachable"
      export CURL_EXIT=7
      When run sh "$(script_path)" "work_mem" "64MB"
      The status should be failure
      The error should include "cannot reach patroni API"
    End

    It "fails when the reload call fails"
      export RELOAD_CODE=503
      When run sh "$(script_path)" "work_mem" "64MB"
      The status should be failure
      The error should include "HTTP 503"
    End

    It "fails when the restart call fails"
      export RESTART_CODE=503
      When run sh "$(script_path)" "shared_buffers" "2GB"
      The status should be failure
      The error should include "HTTP 503"
    End
  End

  Describe "argument validation"
    It "fails when the parameter name is missing"
      When run sh "$(script_path)"
      The status should be failure
      The error should include "missing param name"
    End

    It "fails when the parameter value is missing"
      When run sh "$(script_path)" "work_mem"
      The status should be failure
      The error should include "missing value"
    End
  End
End
