log_level: info
log_format: text

behavior:
  read_only: false
  autocommit: true
  disable_client_multi_statements: false
  dolt_transaction_commit: false
  event_scheduler: "ON"
  auto_gc_behavior:
    enable: false
    archive_level: 0

listener:
  host: 0.0.0.0
  port: 3306
  max_connections: 1000
  back_log: 50
  max_connections_timeout_millis: 60000
  read_timeout_millis: 28800000
  write_timeout_millis: 28800000

max_logged_query_len: 0

data_dir: ${DATA_DIR}
cfg_dir: ${DATA_DIR}/.doltcfg
privilege_file: ${DATA_DIR}/.doltcfg/privileges.db
branch_control_file: ${DATA_DIR}/.doltcfg/branch_control.db

metrics:
  labels: {}
  host: localhost
  port: 11228

remotesapi:
  port: null
  read_only: null

system_variables: {}

user_session_vars: []

jwks: []
