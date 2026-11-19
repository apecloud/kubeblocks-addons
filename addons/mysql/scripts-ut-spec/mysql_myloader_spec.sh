# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "mysql-myloader.sh restore credential wiring"

    restore_env() {
        export DP_DATASAFED_BIN_PATH="/tmp"
        export DP_BACKUP_BASE_PATH="/tmp"
        export DP_BACKUP_NAME="restore-bk"
        export DP_BACKUP_INFO_FILE="/tmp/mysql-myloader-info-$$"
        # DP injects these connection vars into the restore job; the script
        # already relies on DP_DB_HOST / DP_DB_PORT on the same myloader line.
        export DP_DB_HOST="db-host"
        export DP_DB_PORT="3306"
        export DP_DB_USER="dp_user"
        export DP_DB_PASSWORD="dp_pass"
        # component-container-only creds that are NOT injected into the DP job.
        export MYSQL_ADMIN_USER="admin_user"
        export MYSQL_ADMIN_PASSWORD="admin_pass"
        export threads="2"
    }
    BeforeEach "restore_env"

    cleanup() {
        rm -f "${DP_BACKUP_INFO_FILE}" "${DP_BACKUP_INFO_FILE}.exit"
    }
    AfterEach "cleanup"

    It "connects with DP_DB_USER/DP_DB_PASSWORD (matching mysql-mydumper.sh), not MYSQL_ADMIN_*"
        datasafed() { return 0; }
        myloader() { echo "MYLOADER_INVOKED $*"; cat >/dev/null; }
        When run source ../dataprotection/mysql-myloader.sh
        The status should be success
        The stdout should include "MYLOADER_INVOKED"
        The stdout should include "-u dp_user"
        The stdout should include "-p dp_pass"
        The stdout should not include "admin_user"
        The stdout should not include "admin_pass"
    End

    It "does not reference component-only MYSQL_ADMIN_* creds (restore-job asymmetry regression guard)"
        When run grep -F "MYSQL_ADMIN" ../dataprotection/mysql-myloader.sh
        The status should be failure
        The output should equal ""
    End

End
