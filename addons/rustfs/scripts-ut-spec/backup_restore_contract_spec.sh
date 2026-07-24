# shellcheck shell=bash

Describe "RustFS backup/restore contract"
  It "backs up and restores through a certificate-verifying S3 client"
    When run sh ./backup_restore_contract_test.sh
    The status should be success
    The output should include "rustfs backup/restore contract test passed"
    The stderr should include "RUSTFS_TLS_CA_FILE is required for HTTPS"
    The stderr should include "unsupported RUSTFS_SCHEME=ftp"
    The stderr should include "does not exist"
    The stderr should include "installed RustFS TLS CA is empty"
    The stderr should include "failed to read backup size from datasafed"
    The stderr should include "datasafed stat did not report TotalSize"
    The stderr should include "fake mc find failed"
    The stderr should include "unsafe backup artifact path ../escape"
    The stderr should include "failed to inspect backup artifact rustfs-test/objects/a/hello.txt"
  End
End
