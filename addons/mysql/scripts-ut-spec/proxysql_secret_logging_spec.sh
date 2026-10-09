# shellcheck shell=bash
# shellcheck disable=SC2016

Describe "ProxySQL root password disclosure contract"
  script_path="../scripts/configure-proxysql.sh"

  It "never interpolates MYSQL_ROOT_PASSWORD into a log call"
    When call sh -c '! grep -E '\''^[[:space:]]*log .*\$MYSQL_ROOT_PASSWORD'\'' "$1"' sh "$script_path"
    The status should be success
  End

  It "does not enable verbose mysql output for the password-bearing mysql_users statement"
    When call sh -c '! grep -E '\''mysql .*-[^ ]*vvv[^ ]* .*mysql_users'\'' "$1"' sh "$script_path"
    The status should be success
  End
End
