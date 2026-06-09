# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey backup contract"
  script_file="../dataprotection/backup.sh"

  It "builds valkey-cli commands as arrays so passwords are not word-split"
    When call grep -E "(_probe_base|connect_base|s_cli_base)=\\(" "${script_file}"
    The status should be success
    The stdout should include "_probe_base=("
    The stdout should include "connect_base=("
    The stdout should include "s_cli_base=("
  End

  It "does not keep old string command prefixes with interpolated passwords"
    When call grep -E "(connect_url|_probe_base|s_cli)=\"valkey-cli" "${script_file}"
    The status should be failure
  End

  It "does not use unquoted string expansion for CLI commands"
    When call grep -E '^\$\{connect_url\}|\$\{_probe_base\}[^@]' "${script_file}"
    The status should be failure
  End
End
