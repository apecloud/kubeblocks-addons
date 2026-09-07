# shellcheck shell=bash

Describe "MongoDB native TLS integration"
  Include ../scripts/mongodb-common.sh

  It "leaves plaintext clients unchanged when TLS is disabled"
    TLS_ENABLED=false
    When call mongodb_tls_client_options
    The status should be success
    The output should be blank
  End

  It "uses insecure TLS for shell clients when TLS is enabled"
    TLS_ENABLED=true
    When call mongodb_tls_client_options
    The status should be success
    The output should equal "--tls --tlsAllowInvalidCertificates --tlsAllowInvalidHostnames"
  End

  It "does not read certificate files when TLS is disabled"
    TLS_ENABLED=false
    When call prepare_mongodb_tls
    The status should be success
    The output should be blank
  End

  It "leaves server arguments unchanged when TLS is unset"
    unset TLS_ENABLED
    When call mongodb_tls_server_options
    The status should be success
    The output should be blank
  End

  It "leaves server arguments unchanged when TLS is disabled"
    TLS_ENABLED=false
    MONGODB_SERVICE_VERSION=4.0.28
    When call mongodb_tls_server_options
    The status should be success
    The output should be blank
  End

  It "uses TLS-only server arguments with the mounted CA and combined PEM"
    TLS_ENABLED=true
    MONGODB_SERVICE_VERSION=8.0.17
    When call mongodb_tls_server_options
    The status should be success
    The output should equal "--tlsMode requireTLS --tlsCAFile /etc/pki/tls/ca.pem --tlsCertificateKeyFile /etc/mongodb/tls/mongodb.pem --tlsAllowConnectionsWithoutCertificates"
  End

  It "uses legacy server arguments for MongoDB 4.0"
    TLS_ENABLED=true
    MONGODB_SERVICE_VERSION=4.0.28
    When call mongodb_tls_server_options
    The status should be success
    The output should equal "--sslMode requireSSL --sslCAFile /etc/pki/tls/ca.pem --sslPEMKeyFile /etc/mongodb/tls/mongodb.pem --sslAllowConnectionsWithoutCertificates"
  End

  It "uses legacy client arguments for the bundled MongoDB 4.0 shell"
    TLS_ENABLED=true
    MONGODB_SERVICE_VERSION=4.0.28
    When call mongodb_tls_client_options mongo
    The status should be success
    The output should equal "--ssl --sslAllowInvalidCertificates --sslAllowInvalidHostnames"
  End

  It "uses modern client arguments for mongosh even with a MongoDB 4.0 server"
    TLS_ENABLED=true
    MONGODB_SERVICE_VERSION=4.0.28
    When call mongodb_tls_client_options mongosh
    The status should be success
    The output should equal "--tls --tlsAllowInvalidCertificates --tlsAllowInvalidHostnames"
  End
End
