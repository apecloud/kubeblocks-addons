# shellcheck shell=sh

Describe "MySQL lifecycle client argv contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  extract_account_provision_script() {
    helm template test "$(chart_path)" --show-only "templates/$1" |
      awk '
        /^    accountProvision:$/ { in_action = 1 }
        in_action && /^          - \|$/ { in_script = 1; next }
        in_script && /^        targetPodSelector:/ { exit }
        in_script { sub(/^            /, ""); print }
      '
  }

  extract_readiness_script() {
    helm template test "$(chart_path)" --show-only "templates/$1" |
      awk '
        /^        readinessProbe:$/ { in_probe = 1 }
        in_probe && /^              - \|$/ { in_script = 1; next }
        in_script && /^          initialDelaySeconds:/ { exit }
        in_script { sub(/^                /, ""); print }
      '
  }

  run_with_mysql_capture() {
    mode=$1
    template=$2
    tmp_dir=$(mktemp -d)
    argv_file="$tmp_dir/argv"

    cat >"$tmp_dir/mysql" <<'SH'
#!/bin/sh
index=0
for arg do
  printf '%s=%s\n' "$index" "$arg"
  index=$((index + 1))
done >"${MYSQL_ARGV_FILE:?}"
SH
    chmod +x "$tmp_dir/mysql"

    if [ "$mode" = account ]; then
      script=$(extract_account_provision_script "$template")
    else
      script=$(extract_readiness_script "$template")
    fi

    PATH="$tmp_dir:$PATH" \
      MYSQL_ARGV_FILE="$argv_file" \
      MYSQL_ROOT_USER=root \
      MYSQL_ROOT_PASSWORD='alpha beta[*]' \
      KB_ACCOUNT_STATEMENT='SELECT 1' \
      bash -c "$script" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      cat "$argv_file"
    fi
    rm -rf "$tmp_dir"
    return "$rc"
  }

  It "preserves credentials as single mysql arguments in accountProvision"
    When call run_with_mysql_capture account cmpd-mysql80.yaml
    The status should be success
    The output should include "0=--user=root"
    The output should include "1=--password=alpha beta[*]"
    The output should include "2=--port=3306"
    The output should include "3=--host=127.0.0.1"
    The output should include "4=--execute=SELECT 1"
    The lines of output should equal 5
  End

  It "preserves credentials as single mysql arguments in ORC accountProvision"
    When call run_with_mysql_capture account cmpd-mysql80-orc.yaml
    The status should be success
    The output should include "0=--user=root"
    The output should include "1=--password=alpha beta[*]"
    The output should include "2=--port=3306"
    The output should include "3=--host=127.0.0.1"
    The output should include "4=--execute=SELECT 1;"
    The lines of output should equal 5
  End

  It "preserves credentials as single mysql arguments in ORC readiness"
    When call run_with_mysql_capture readiness cmpd-mysql80-orc.yaml
    The status should be success
    The output should include "0=--user=root"
    The output should include "1=--password=alpha beta[*]"
    The output should include "2=--port=3306"
    The output should include "3=--host=127.0.0.1"
    The output should include "4=--execute=SELECT 1;"
    The lines of output should equal 5
  End
End
