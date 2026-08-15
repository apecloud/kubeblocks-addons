# shellcheck shell=bash

Describe "MySQL accountProvision SQL literal contract"
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

  run_account_provision() {
    template=$1
    tmp_dir=$(mktemp -d)

    cat >"${tmp_dir}/mysql" <<'SH'
#!/bin/sh
for arg do
  query=$arg
done
printf '%s\n' "$query"
SH
    chmod +x "${tmp_dir}/mysql"

    script=$(extract_account_provision_script "${template}") || return
    PATH="${tmp_dir}:${PATH}" \
      MYSQL_ROOT_USER=root \
      MYSQL_ROOT_PASSWORD=root-password \
      KB_ACCOUNT_NAME=kbprobe \
      KB_ACCOUNT_PASSWORD="pa'ss" \
      KB_ACCOUNT_STATEMENT="CREATE USER \${KB_ACCOUNT_NAME} IDENTIFIED BY '\${KB_ACCOUNT_PASSWORD}';" \
      bash -c "${script}" 2>/dev/null
    rc=$?

    rm -rf "${tmp_dir}"
    return "${rc}"
  }

  It "escapes an overridden account password in standard accountProvision SQL"
    When call run_account_provision cmpd-mysql80.yaml
    The status should be success
    The output should include "CREATE USER kbprobe IDENTIFIED BY 'pa''ss';"
  End

  It "escapes an overridden account password in ORC accountProvision SQL"
    When call run_account_provision cmpd-mysql80-orc.yaml
    The status should be success
    The output should include "CREATE USER kbprobe IDENTIFIED BY 'pa''ss';"
  End
End
