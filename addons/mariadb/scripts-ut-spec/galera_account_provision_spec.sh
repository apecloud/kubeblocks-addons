# shellcheck shell=sh
# Execution-level test of the galera accountProvision SQL escaping. It extracts
# the ACTUAL accountProvision command from cmpd-galera.yaml (that block is plain
# shell with no Go-template interpolation, so raw extraction is faithful), runs
# it with a mocked `mariadb` that captures the final statement passed via -e,
# and asserts the account value lands inside a properly-closed single-quoted
# literal for adversarial inputs. Because it executes the shipped script, a
# drift in the template's escaping would fail this test.

Describe "galera accountProvision SQL escaping (shipped implementation)"
  setup() {
    AP_DIR="$(mktemp -d)"
    CMPD="$(printf '%s/addons/mariadb/templates/cmpd-galera.yaml' "${SHELLSPEC_CWD:?}")"
    # Extract the accountProvision command block (plain shell, no templating).
    python3 - "${CMPD}" > "${AP_DIR}/account-provision.sh" <<'PYEOF'
import sys, re
lines = open(sys.argv[1]).read().splitlines()
out, in_ap, in_block, bi = [], False, False, None
for ln in lines:
    if re.match(r'\s*accountProvision:\s*$', ln):
        in_ap = True; continue
    if in_ap and re.match(r'\s*roleProbe:\s*$', ln):
        break
    if in_ap and re.match(r'\s*- \|\s*$', ln):
        in_block = True; continue
    if in_block:
        if ln.strip() == "":
            out.append(""); continue
        ind = len(ln) - len(ln.lstrip())
        if bi is None: bi = ind
        if ind < bi and ln.strip(): break
        out.append(ln[bi:])
sys.stdout.write("\n".join(out) + "\n")
PYEOF
    # Mock mariadb: capture the statement passed to -e into a file.
    cat > "${AP_DIR}/mariadb" <<MOCK
#!/bin/sh
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-e" ]; then shift; printf '%s' "\$1" > "${AP_DIR}/statement"; fi
  shift
done
MOCK
    chmod +x "${AP_DIR}/mariadb"
  }
  BeforeEach setup
  cleanup() { rm -rf "${AP_DIR}"; }
  AfterEach cleanup

  run_provision() {
    KB_ACCOUNT_NAME="$1"
    KB_ACCOUNT_PASSWORD="$2"
    KB_ACCOUNT_STATEMENT="CREATE USER '\${KB_ACCOUNT_NAME}'@'%' IDENTIFIED BY '\${KB_ACCOUNT_PASSWORD}'; GRANT ALL ON \${ALL_DB} TO '\${KB_ACCOUNT_NAME}'@'%';"
    MARIADB_ROOT_USER="root"
    MARIADB_ROOT_PASSWORD="rootpw"
    export KB_ACCOUNT_NAME KB_ACCOUNT_PASSWORD KB_ACCOUNT_STATEMENT MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD
    PATH="${AP_DIR}:${PATH}" sh "${AP_DIR}/account-provision.sh"
    cat "${AP_DIR}/statement"
  }

  It "doubles a single quote in the password so it stays inside the literal"
    When call run_provision "app" "p'x"
    The output should include "IDENTIFIED BY 'p''x'"
    The output should not include "IDENTIFIED BY 'p'x'"
  End

  It "neutralizes a SQL injection payload in the password"
    When call run_provision "app" "p'; DROP TABLE x; --"
    The output should include "IDENTIFIED BY 'p''; DROP TABLE x; --'"
  End

  It "doubles a trailing backslash so it cannot escape the closing quote"
    When call run_provision "app" 'pa\'
    The output should include "IDENTIFIED BY 'pa\\\\'"
  End

  It "preserves ampersand and pipe verbatim inside the literal"
    When call run_provision "app" 'a|b&c'
    The output should include "IDENTIFIED BY 'a|b&c'"
  End

  It "doubles a single quote in the account name"
    When call run_provision "ev'il" "pw"
    The output should include "CREATE USER 'ev''il'@'%'"
  End
End
