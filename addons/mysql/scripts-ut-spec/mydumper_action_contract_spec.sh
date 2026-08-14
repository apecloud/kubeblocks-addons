# shellcheck shell=sh

Describe "MySQL mydumper ActionSet contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  helm_not_available() { ! command -v helm >/dev/null 2>&1; }
  Skip if "helm not available" helm_not_available

  restore_parameters() {
    helm template test "$(chart_path)" \
      --show-only templates/actionset-mydumper.yaml | awk '
        /^  restore:$/ { in_restore = 1; next }
        in_restore && /^    withParameters:$/ { in_parameters = 1; next }
        in_parameters && /^      - / { print $2; next }
        in_parameters { exit }
        END { if (!in_parameters) exit 1 }
      '
  }

  verify_restore_parameters_are_consumed() {
    parameters=$(restore_parameters) || return 1
    expected=$(printf '%s\n' threads tables drop_table)
    [ "${parameters}" = "${expected}" ] || return 1

    script=$(awk '!/^[[:space:]]*#/' "$(chart_path)/dataprotection/mysql-myloader.sh") || return 1
    for parameter in ${parameters}; do
      printf '%s\n' "${script}" |
        grep -Eq '[$][{]?'"${parameter}"'([}]|[^A-Za-z0-9_])' || return 1
    done
  }

  It "advertises only parameters consumed by the myloader restore script"
    When call verify_restore_parameters_are_consumed
    The status should be success
  End
End
