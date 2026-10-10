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

  It "archives only the BGSAVE snapshot and the ACL file"
    When call grep -F 'tar -cvf - "${backup_files[@]}"' "${script_file}"
    The status should be success
    The stdout should include 'backup_files'
  End

  It "does not archive the live data directory wholesale (torn-AOF risk)"
    # Tarring ./ captures appendonlydir/ mid-write; on restore the engine
    # prefers the AOF over the consistent BGSAVE RDB.
    When call grep -F 'tar -cvf - ./ ' "${script_file}"
    The status should be failure
  End
  It "embeds cluster-meta with engine-truth shard count in cluster mode"
    When call grep -E 'cluster_enabled|source_shards=|cluster-meta' "${script_file}"
    The status should be success
    The stdout should include "cluster_enabled"
    The stdout should include "source_shards="
    The stdout should include "cluster-meta"
  End
End
