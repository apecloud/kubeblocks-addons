log_level: info
data_dir: ${DATA_DIR}
cfg_dir: ${DATA_DIR}/.doltcfg
privilege_file: ${DATA_DIR}/.doltcfg/privileges.db
branch_control_file: ${DATA_DIR}/.doltcfg/branch_control.db

listener:
  host: 0.0.0.0
  port: 3306

behavior:
  read_only: false

metrics:
  labels: {}
  host: 0.0.0.0
  port: 11228