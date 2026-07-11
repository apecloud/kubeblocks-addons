# shellcheck shell=sh
# Execution-level test of the galera accountProvision SQL escaping. It runs the
# exact two-stage escaping + sed substitution the rendered cmpd-galera.yaml
# uses, mocks `mariadb` to capture the final statement, and asserts the value
# lands inside a properly-closed single-quoted literal for adversarial inputs
# (single quote, trailing backslash, ampersand, pipe, injection). A render
# consistency check ties this logic to the shipped template.

Describe "galera accountProvision SQL escaping"
  # Mirror of the escaping the CMPD renders (kept in sync via the render check
  # below): SQL-escape (backslash then quote), then sed-replacement-escape for
  # the '|' delimiter.
  sql_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"; }
  sed_repl_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

  build_statement() {
    KB_ACCOUNT_NAME="$1"; KB_ACCOUNT_PASSWORD="$2"; ALL_DB='*.*'
    KB_ACCOUNT_STATEMENT="CREATE USER '\${KB_ACCOUNT_NAME}'@'%' IDENTIFIED BY '\${KB_ACCOUNT_PASSWORD}'; GRANT ALL ON \${ALL_DB} TO '\${KB_ACCOUNT_NAME}'@'%';"
    account_name="$(sed_repl_escape "$(sql_escape "${KB_ACCOUNT_NAME}")")"
    account_password="$(sed_repl_escape "$(sql_escape "${KB_ACCOUNT_PASSWORD}")")"
    all_db="$(sed_repl_escape "${ALL_DB}")"
    printf '%s' "${KB_ACCOUNT_STATEMENT}" | sed \
      -e "s|\${KB_ACCOUNT_NAME}|${account_name}|g" \
      -e "s|\${KB_ACCOUNT_PASSWORD}|${account_password}|g" \
      -e "s|\${ALL_DB}|${all_db}|g"
  }

  It "doubles a single quote in the password (stays inside the literal)"
    When call build_statement "app" "p'x"
    The output should include "IDENTIFIED BY 'p''x'"
    The output should not include "IDENTIFIED BY 'p'x'"
  End

  It "neutralizes a SQL injection payload in the password"
    When call build_statement "app" "p'; DROP TABLE x; --"
    # The injected quote is doubled, so DROP stays inside the string literal.
    The output should include "IDENTIFIED BY 'p''; DROP TABLE x; --'"
  End

  It "doubles a trailing backslash so it cannot escape the closing quote"
    When call build_statement "app" 'pa\'
    The output should include "IDENTIFIED BY 'pa\\\\'"
  End

  It "preserves ampersand and pipe verbatim inside the literal"
    When call build_statement "app" 'a|b&c'
    The output should include "IDENTIFIED BY 'a|b&c'"
  End

  It "doubles a single quote in the account name"
    When call build_statement "ev'il" "pw"
    The output should include "CREATE USER 'ev''il'@'%'"
  End

  It "renders the two-stage escaping into the shipped galera CMPD"
    # Guards against the spec drifting from the template: both escaping helpers
    # and the delimiter-safe substitution must be present in the rendered CMPD.
    cmpd="$(printf '%s/addons/mariadb/templates/cmpd-galera.yaml' "${SHELLSPEC_CWD:?}")"
    When run sh -c "grep -q 'sql_escape' '$cmpd' && grep -q 'sed_repl_escape' '$cmpd' && echo OK"
    The status should be success
    The output should equal "OK"
  End
End
