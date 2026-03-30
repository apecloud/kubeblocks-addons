log_level: info
data_dir: ${DATA_DIR}

listener:
  host: 0.0.0.0
  port: 3306

behavior:
  read_only: false

metrics:
  labels: {}
  host: 0.0.0.0
  port: 11228

cluster:
  bootstrap_role: ${BOOTSTRAP_ROLE}
  bootstrap_epoch: 1

  remotesapi:
    port: ${REMOTES_API_PORT}

  standby_remotes:
    - name: standby
      remote_url_template: http://${STANDBY_HOST}.${HEADLESS_SERVICE_NAME}:${REMOTES_API_PORT}/{database}
