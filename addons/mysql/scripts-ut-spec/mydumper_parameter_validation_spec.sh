# shellcheck shell=bash disable=SC2329

Describe "MySQL mydumper parameter validation"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  verify_invalid_booleans_fail_before_tool_invocation() {
    for parameter in trx_tables no_data; do
      root=$(mktemp -d "${TMPDIR:-/tmp}/mysql-mydumper-boolean.XXXXXX") || return 1

      (
        datasafed() {
          if [ "$1" = "push" ]; then
            cat >/dev/null
          fi
        }
        mydumper() {
          touch "${TOOL_CALLED}"
        }
        export -f datasafed mydumper
        export TOOL_CALLED="${root}/mydumper-called"
        export DP_DATASAFED_BIN_PATH="/bin"
        export DP_BACKUP_BASE_PATH="/repo/current"
        export DP_BACKUP_NAME="current"
        export DP_BACKUP_INFO_FILE="${root}/progress"
        export DP_DB_HOST="mysql"
        export DP_DB_PORT="3306"
        export DP_DB_USER="backup"
        export DP_DB_PASSWORD="secret"
        export threads=""
        export tables=""
        export trx_tables="false"
        export no_data="false"
        export databases=""
        case "${parameter}" in
          trx_tables) export trx_tables="invalid" ;;
          no_data) export no_data="invalid" ;;
        esac
        bash "$(chart_path)/dataprotection/mysql-mydumper.sh" >/dev/null 2>&1
      )
      status=$?

      [ "${status}" -ne 0 ] && [ ! -e "${root}/mydumper-called" ] || {
        rm -rf "${root}"
        return 1
      }
      rm -rf "${root}"
    done
  }

  It "rejects malformed boolean values before invoking mydumper"
    When call verify_invalid_booleans_fail_before_tool_invocation
    The status should be success
  End
End
