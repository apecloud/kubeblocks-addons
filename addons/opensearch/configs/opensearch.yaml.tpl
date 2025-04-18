cluster.name: {{ .CLUSTER_NAME }}

# Bind to all interfaces because we don't know what IP address Docker will assign to us.
network.host: 0.0.0.0

# Setting network.host to a non-loopback address enables the annoying bootstrap checks. "Single-node" mode disables them again.
# Implicitly done if ".singleNode" is set to "true".
# discovery.type: single-node

# Start OpenSearch Security Demo Configuration
# WARNING: revise all the lines below before you go into production
plugins:
  security:
    ssl:
      transport:
        pemcert_filepath: esnode.pem
        pemkey_filepath: esnode-key.pem
        pemtrustedcas_filepath: root-ca.pem
        enforce_hostname_verification: false
      http:
        enabled: true
        pemcert_filepath: esnode.pem
        pemkey_filepath: esnode-key.pem
        pemtrustedcas_filepath: root-ca.pem
    allow_unsafe_democertificates: true
    allow_default_init_securityindex: true
    authcz:
      admin_dn:
        - CN=kirk,OU=client,O=client,L=test,C=de
    audit.type: internal_opensearch
    enable_snapshot_restore_privilege: true
    check_snapshot_restore_write_privileges: true
    restapi:
      roles_enabled: ["all_access", "security_rest_api_access"]
    system_indices:
      enabled: true
      indices:
        [
          ".opendistro-alerting-config",
          ".opendistro-alerting-alert*",
          ".opendistro-anomaly-results*",
          ".opendistro-anomaly-detector*",
          ".opendistro-anomaly-checkpoints",
          ".opendistro-anomaly-detection-state",
          ".opendistro-reports-*",
          ".opendistro-notifications-*",
          ".opendistro-notebooks",
          ".opendistro-asynchronous-search-response*",
        ]
######## End OpenSearch Security Demo Configuration ########
