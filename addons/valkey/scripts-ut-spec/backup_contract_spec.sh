# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey backup contract"
  script_file="../dataprotection/backup.sh"

  It "builds valkey-cli commands as arrays so passwords are not word-split"
    When call grep -E "(_probe_base|connect_url|s_cli)=\\(" "${script_file}"
    The status should be success
    The stdout should include "_probe_base=("
    The stdout should include "connect_url=("
    The stdout should include "s_cli=("
  End

  It "does not keep old string command prefixes with interpolated passwords"
    When call grep -E "(connect_url|_probe_base|s_cli)=\"valkey-cli" "${script_file}"
    The status should be failure
  End

  It "does not use unquoted string expansion for CLI commands"
    When call grep -E '^\$\{connect_url\}|\$\{_probe_base\}[^@]' "${script_file}"
    The status should be failure
  End

  It "waits for BGSAVE to finish before archiving"
    When call grep -F 'rdb_bgsave_in_progress' "${script_file}"
    The status should be success
    The stdout should include "rdb_bgsave_in_progress"
  End

  It "archives the whole data directory, redis addon parity"
    # The redis addon tars ./ and pushes it as one zstd archive; the AOF is
    # archived together with the RDB (a tar that races with an AOF rewrite
    # exits non-zero and the backup framework retries).
    When call grep -F 'tar -cvf - ./ | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst"' "${script_file}"
    The status should be success
    The stdout should include '.tar.zst'
  End

  It "documents the AOF-archived-together trade-off"
    When call grep -F 'the AOF is archived together with the RDB' "${script_file}"
    The status should be success
    The stdout should include "archived together with the RDB"
  End

  It "pushes the Sentinel ACL beside the archive"
    When call grep -F 'datasafed push -z zstd-fastest /tmp/sentinel.acl "sentinel.acl"' "${script_file}"
    The status should be success
    The stdout should include "sentinel.acl"
  End

  It "reports the backup size read back from the repository"
    When call grep -F 'datasafed stat /' "${script_file}"
    The status should be success
    The stdout should include "datasafed stat"
  End

  It "touches the failure marker file when the script exits non-zero"
    When call grep -F 'touch "${DP_BACKUP_INFO_FILE}.exit"' "${script_file}"
    The status should be success
    The stdout should include ".exit"
  End
End
