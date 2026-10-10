#!/usr/bin/env bash

# 2026-06-23 Reason: fixed-address HA needs a yasboot-driven empty-PVC path instead of standalone database creation; Purpose: bootstrap one primary plus N standby nodes from stable hostNetwork addresses.
# Time: 2026-06-23.
set -euo pipefail

WORK_DIR="${WORK_DIR:-/home/yashan}"
YASDB_MOUNT_HOME="${YASDB_MOUNT_HOME:-/home/yashan/mydb}"
YASDB_HA_CLUSTER_NAME="${YASDB_HA_CLUSTER_NAME:?YASDB_HA_CLUSTER_NAME is required}"
YASDB_HA_NODE_ID="${YASDB_HA_NODE_ID:?YASDB_HA_NODE_ID is required}"
YASDB_HA_NODE_ROLE="${YASDB_HA_NODE_ROLE:?YASDB_HA_NODE_ROLE is required}"
YASDB_HA_NODE_IP_LIST="${YASDB_HA_NODE_IP_LIST:?YASDB_HA_NODE_IP_LIST is required}"
YASDB_HA_DB_PORT="${YASDB_HA_DB_PORT:-2688}"
YASDB_HA_OM_PORT="${YASDB_HA_OM_PORT:-2675}"
YASDB_HA_AGENT_PORT="${YASDB_HA_AGENT_PORT:-$((YASDB_HA_OM_PORT + 1))}"
YASHANDB_SSHD_PORT="${YASHANDB_SSHD_PORT:-3222}"
YASDB_PASSWORD="${YASDB_PASSWORD:-yasdb_123}"

YASBOOT_HOME="${YASBOOT_HOME:-/opt/yasboot-package}"
YASBOOT_BIN="${YASBOOT_BIN:-${YASBOOT_HOME}/om/bin/yasboot}"
YASBOOT_USER_HOME="${YASBOOT_USER_HOME:-/home/yashan}"
YASBOOT_ENV_DIR="${YASBOOT_ENV_DIR:-${YASBOOT_USER_HOME}/.yasboot}"
YASBOOT_ENV_FILE="${YASBOOT_ENV_DIR}/${YASDB_HA_CLUSTER_NAME}.env"
YASBOOT_HOME_LINK="${YASBOOT_ENV_DIR}/${YASDB_HA_CLUSTER_NAME}_yasdb_home"
YASDB_DATA_PATH="${YASDB_DATA_PATH:-${YASDB_MOUNT_HOME}/yasdb_data}"
BOOTSTRAP_WORK_DIR="${YASDB_MOUNT_HOME}/.fixed-ha-bootstrap"
YASDB_FIXED_HA_BOOTSTRAP_DONE="${YASDB_MOUNT_HOME}/.fixed-ha-bootstrap-done"
BOOTSTRAP_PACKAGE_DIR="${BOOTSTRAP_WORK_DIR}/${YASDB_HA_CLUSTER_NAME}"
HOSTS_TOML="${BOOTSTRAP_PACKAGE_DIR}/hosts.toml"
CLUSTER_TOML="${BOOTSTRAP_PACKAGE_DIR}/${YASDB_HA_CLUSTER_NAME}.toml"

# 2026-06-23 Reason: proof commands usually run yasboot from /opt/yasboot-package/bin; Purpose: make explicit yasboot commands work even when the image does not preconfigure PATH.
# Time: 2026-06-23.
export PATH="${YASBOOT_HOME}/bin:${PATH}"

log() {
  printf '[fixed-ha-bootstrap] %s\n' "$*"
}

start_sshd() {
  local sshd_bin

  if pgrep -x sshd >/dev/null 2>&1; then
    log "sshd already running"
    return 0
  fi

  # 2026-06-23 Reason: fixed-address HA pods need the entrypoint's setup but not its long-running restore loop; Purpose: prepare SSH and yasboot synchronously before bootstrap starts.
  # Time: 2026-06-23.
  chown -R root:root /etc/crypto-policies /etc/ssh 2>/dev/null || true
  chmod -R go-w /etc/crypto-policies /etc/ssh 2>/dev/null || true
  mkdir -p /run/sshd /var/empty/sshd /home/yashan/.ssh "${YASBOOT_HOME}"
  chown root:root /var/empty/sshd
  chmod 755 /var/empty/sshd
  chmod 700 /home/yashan/.ssh

  if [ -n "${YASHANDB_SSH_PRIVATE_KEY:-}" ]; then
    printf '%s\n' "${YASHANDB_SSH_PRIVATE_KEY}" > /home/yashan/.ssh/id_rsa
    chmod 600 /home/yashan/.ssh/id_rsa
  fi

  if [ -n "${YASHANDB_AUTHORIZED_KEY:-}" ]; then
    printf '%s\n' "${YASHANDB_AUTHORIZED_KEY}" > /home/yashan/.ssh/authorized_keys
    chmod 600 /home/yashan/.ssh/authorized_keys
  fi
  chown -R yashan:yashan /home/yashan/.ssh

  if [ ! -x "${YASBOOT_BIN}" ]; then
    tar -xzf /opt/yashandb-23.4.1.109-linux-aarch64.tar.gz -C "${YASBOOT_HOME}"
    chmod +x "${YASBOOT_HOME}/bin/yasboot" "${YASBOOT_BIN}" 2>/dev/null || true
  fi

  sshd_bin="$(command -v sshd || true)"
  if [ -n "${sshd_bin}" ]; then
    mkdir -p /var/run/sshd
    ssh-keygen -A >/tmp/fixed-ha-ssh-keygen.log 2>&1 || true
    cat > /tmp/fixed-ha-sshd_config <<EOF
Port ${YASHANDB_SSHD_PORT}
ListenAddress 0.0.0.0
HostKey /etc/ssh/ssh_host_ed25519_key
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PubkeyAuthentication yes
UsePAM no
PermitRootLogin no
StrictModes no
Subsystem sftp internal-sftp
EOF
    # 2026-06-23 Reason: OpenSSH in the validation image rejects relative re-exec through PATH; Purpose: start sshd with an absolute binary path so fixed-address bootstrap pods do not crash loop.
    # 2026-06-23 Reason: the image entrypoint also mutates /opt/yasboot-package while bootstrap runs; Purpose: start only sshd here and avoid concurrent yasboot binary changes.
    # Time: 2026-06-23.
    "${sshd_bin}" -f /tmp/fixed-ha-sshd_config
    return 0
  fi

  log "sshd is not available in this image"
  return 1
}

count_nodes() {
  # 2026-06-23 Reason: comma splitting without a trailing newline drops the final address in shell read/count paths; Purpose: keep yasboot --node aligned with the full fixed-address topology.
  # Time: 2026-06-23.
  printf '%s\n' "${YASDB_HA_NODE_IP_LIST}" | tr ',' '\n' | sed '/^$/d' | wc -l | tr -d ' '
}

wait_for_peer() {
  local ip="$1"
  local deadline="${2:-300}"
  local start
  start="$(date +%s)"

  while true; do
    if command -v nc >/dev/null 2>&1; then
      if nc -z -w 2 "$ip" "${YASHANDB_SSHD_PORT}" >/dev/null 2>&1; then
        log "peer ${ip}:${YASHANDB_SSHD_PORT} is reachable"
        return 0
      fi
    else
      if timeout 2 bash -c ":</dev/tcp/${ip}/${YASHANDB_SSHD_PORT}" >/dev/null 2>&1; then
        log "peer ${ip}:${YASHANDB_SSHD_PORT} is reachable"
        return 0
      fi
    fi

    if [ $(( "$(date +%s)" - start )) -ge "$deadline" ]; then
      log "timed out waiting for peer ${ip}:${YASHANDB_SSHD_PORT}"
      return 1
    fi
    sleep 3
  done
}

wait_for_all_peers() {
  local ip
  # 2026-06-23 Reason: the last fixed-address peer may not be newline-terminated; Purpose: ensure every peer is waited before primary runs yasboot deploy.
  # Time: 2026-06-23.
  printf '%s\n' "${YASDB_HA_NODE_IP_LIST}" | tr ',' '\n' | sed '/^$/d' | while IFS= read -r ip; do
    wait_for_peer "$ip" 300
  done
}

is_primary_node() {
  [ "${YASDB_HA_NODE_ROLE}" = "primary" ] || [ "${YASDB_HA_NODE_ID}" = "1-1" ]
}

already_bootstrapped() {
  [ -f "${YASDB_FIXED_HA_BOOTSTRAP_DONE}" ] && [ -d "${YASDB_DATA_PATH}" ]
}

write_yasboot_env() {
  # 2026-06-23 Reason: yasboot writes its per-cluster env under the container home, which is lost after a Pod rebuild; Purpose: reconstruct the minimal yasboot runtime contract from stable PVC/bootstrap metadata before starting an existing node.
  # Contract: this restores /home/yashan/.yasboot metadata for rolling restart recovery.
  # Time: 2026-06-23.
  mkdir -p "${YASBOOT_ENV_DIR}"
  cat > "${YASBOOT_ENV_FILE}" <<EOF
cluster="${YASDB_HA_CLUSTER_NAME}"
om_addr="$(printf '%s\n' "${YASDB_HA_NODE_IP_LIST}" | tr ',' '\n' | sed '/^$/d' | head -1):${YASDB_HA_OM_PORT}"
version="23.4.1.109"
same_version=false
base_path="${YASDB_MOUNT_HOME}/23.4.1.109"
max_ac_sql_size=209715200
max_ac_sql_rows=1000000
EOF
  ln -sfn "${YASDB_MOUNT_HOME}/23.4.1.109" "${YASBOOT_HOME_LINK}"
  chown -R yashan:yashan "${YASBOOT_ENV_DIR}" || true
}

node_data_path() {
  printf '%s/db-%s' "${YASDB_DATA_PATH}" "${YASDB_HA_NODE_ID}"
}

host_id() {
  local node_index
  node_index="${YASDB_HA_NODE_ID#*-}"
  printf 'host%04d' "${node_index}"
}

local_om_config_exists() {
  # 2026-06-23 Reason: live rolling restart showed only the yasboot OM host owns om/<cluster>/conf/yasom.toml; Purpose: restore non-OM DB nodes without failing on missing local OM metadata.
  # Contract: non-OM nodes must skip yasom start and still use the cluster OM address from .yasboot for node start.
  # Time: 2026-06-23.
  [ -f "${YASDB_MOUNT_HOME}/23.4.1.109/om/${YASDB_HA_CLUSTER_NAME}/conf/yasom.toml" ]
}

ensure_hosts_toml() {
  local ip
  local index

  if [ -f "${HOSTS_TOML}" ]; then
    return 0
  fi

  # 2026-06-23 Reason: live rolling restart showed non-primary PVCs do not keep .fixed-ha-bootstrap/hosts.toml; Purpose: regenerate the minimal yasboot host inventory needed to restart the local agent without reinstalling or redeploying the cluster.
  # Contract: this only restores yasboot process input for existing fixed-address nodes and must not run package install, cluster deploy, or rebuild.
  # Time: 2026-06-23.
  mkdir -p "${BOOTSTRAP_PACKAGE_DIR}"
  cat > "${HOSTS_TOML}" <<EOF
uuid = ""
cluster = "${YASDB_HA_CLUSTER_NAME}"
yas_type = "SE"
secret_key = "$(yasboot_secret_key)"
add_yasdba = true
plugins = ["all"]

[om]
  hostid = "host0001"
  [om.config]
    LISTEN_ADDR = "$(printf '%s\n' "${YASDB_HA_NODE_IP_LIST}" | tr ',' '\n' | sed '/^$/d' | head -1):${YASDB_HA_OM_PORT}"

EOF

  index=1
  printf '%s\n' "${YASDB_HA_NODE_IP_LIST}" | tr ',' '\n' | sed '/^$/d' | while IFS= read -r ip; do
    cat >> "${HOSTS_TOML}" <<EOF
[[host]]
  hostid = "$(printf 'host%04d' "${index}")"
  group = "yashan"
  user = "yashan"
  ip = "${ip}"
  port = ${YASHANDB_SSHD_PORT}
  path = "${YASDB_MOUNT_HOME}/23.4.1.109"
  no_password = true
  log_path = "${YASDB_MOUNT_HOME}/log"
  [host.yasagent]
    [host.yasagent.config]
      LISTEN_ADDR = "${ip}:${YASDB_HA_AGENT_PORT}"

EOF
    index=$((index + 1))
  done
  chown -R yashan:yashan "${BOOTSTRAP_WORK_DIR}" || true
}

yasboot_secret_key() {
  local key
  key="$(sed -n 's/^secret_key = "\(.*\)"/\1/p' "${HOSTS_TOML}" 2>/dev/null | head -1)"
  if [ -n "${key}" ]; then
    printf '%s' "${key}"
    return 0
  fi
  printf '                '
}

write_probe_env() {
  local node_data
  node_data="$(node_data_path)"

  if [ ! -d "${node_data}/config" ]; then
    return 1
  fi

  # 2026-06-23 Reason: yasboot HA stores each node under yasdb_data/db-<node-id> while existing KubeBlocks probes source .temp.ini; Purpose: bridge fixed-address HA layout to check_alive.sh and check_role.sh without changing standalone mode.
  # Time: 2026-06-23.
  cat > "${YASDB_MOUNT_HOME}/.temp.ini" <<EOF
YASDB_HOME=${YASDB_MOUNT_HOME}/23.4.1.109
YASDB_DATA=${node_data}
EOF
  mkdir -p "${YASDB_MOUNT_HOME}/23.4.1.109/conf"
  cat > "${YASDB_MOUNT_HOME}/23.4.1.109/conf/yasdb.bashrc" <<EOF
export YASDB_HOME=${YASDB_MOUNT_HOME}/23.4.1.109
export YASDB_DATA=${node_data}
export PATH=\$YASDB_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$YASDB_HOME/lib:\$LD_LIBRARY_PATH
EOF
  chown yashan:yashan "${YASDB_MOUNT_HOME}/.temp.ini" || true
  chown -R yashan:yashan "${YASDB_MOUNT_HOME}/23.4.1.109/conf" || true
}

wait_for_local_deploy() {
  local deadline="${1:-900}"
  local start
  start="$(date +%s)"

  while true; do
    if write_probe_env || already_bootstrapped || [ -f "${YASDB_MOUNT_HOME}/.temp.ini" ]; then
      touch "${YASDB_FIXED_HA_BOOTSTRAP_DONE}"
      log "local deploy artifacts are present"
      return 0
    fi
    if [ $(( "$(date +%s)" - start )) -ge "$deadline" ]; then
      log "timed out waiting for local deploy artifacts"
      return 1
    fi
    sleep 5
  done
}

wait_for_local_ready() {
  local deadline="${1:-300}"
  local start
  start="$(date +%s)"

  while true; do
    if bash /home/yashan/kbscripts/check_alive.sh >/tmp/fixed-ha-check-alive.log 2>&1 &&
       bash /home/yashan/kbscripts/check_role.sh >/tmp/fixed-ha-check-role.log 2>&1; then
      log "local node is ready after restore"
      return 0
    fi

    if [ $(( "$(date +%s)" - start )) -ge "$deadline" ]; then
      log "timed out waiting for restored local node readiness"
      cat /tmp/fixed-ha-check-alive.log 2>/dev/null || true
      cat /tmp/fixed-ha-check-role.log 2>/dev/null || true
      return 1
    fi
    sleep 5
  done
}

prepare_yasboot_permissions() {
  # 2026-06-23 Reason: live KubeBlocks bootstrap showed yasboot writes om/yasboot.log before executing commands as the yashan user; Purpose: make the package home match the earlier proof environment instead of failing with permission denied.
  # Time: 2026-06-23.
  mkdir -p "${YASBOOT_HOME}/om"
  touch "${YASBOOT_HOME}/om/yasboot.log"
  chown -R yashan:YASDBA "${YASBOOT_HOME}" || chown -R yashan:yashan "${YASBOOT_HOME}" || true
  chmod -R u+rwX,g+rwX "${YASBOOT_HOME}" || true
}

restore_bootstrapped_node() {
  log "restoring already bootstrapped local node ${YASDB_HA_NODE_ID}"
  # 2026-06-23 Reason: rolling restart deletes the container home but keeps the PVC data directory; Purpose: restore only this node's yasboot environment and process without running rebuild or cluster-wide orchestration.
  # Time: 2026-06-23.
  prepare_yasboot_permissions
  write_yasboot_env
  write_probe_env
  # 2026-06-23 Reason: yasboot node start first connects to the local OM endpoint, which is also lost after Pod rebuild; Purpose: restore local OM and agent before starting the database node.
  # Contract: these commands are the fixed-address rolling restart equivalent of `yasboot process yasom start` and `yasboot process yasagent start -t`.
  # Time: 2026-06-23.
  if local_om_config_exists; then
    su -s /bin/bash - yashan -c "cd '${YASBOOT_HOME}' && '${YASBOOT_BIN}' process yasom start -c '${YASDB_HA_CLUSTER_NAME}'"
  else
    log "local OM config is absent on node ${YASDB_HA_NODE_ID}; skipping yasom start"
  fi
  ensure_hosts_toml
  if ! pgrep -f "yasagent .* -c ${YASDB_HA_CLUSTER_NAME} .*--host-id $(host_id)" >/dev/null 2>&1; then
    su -s /bin/bash - yashan -c "cd '${YASBOOT_HOME}' && '${YASBOOT_BIN}' process yasagent start -c '${YASDB_HA_CLUSTER_NAME}' --hostid '$(host_id)' -t '${HOSTS_TOML}'"
  fi
  # Contract: this command is the fixed-address rolling restart equivalent of `yasboot node start`.
  su -s /bin/bash - yashan -c "cd '${YASBOOT_HOME}' && '${YASBOOT_BIN}' node start -c '${YASDB_HA_CLUSTER_NAME}' -n '${YASDB_HA_NODE_ID}' -u sys -p '${YASDB_PASSWORD}' --disable"
  wait_for_local_ready 300
}

run_yasboot_primary_bootstrap() {
  local node_count
  node_count="$(count_nodes)"

  if [ -z "${YASHANDB_SSH_PRIVATE_KEY:-}" ]; then
    log "YASHANDB_SSH_PRIVATE_KEY is required on the primary node for yasboot package install"
    return 1
  fi

  mkdir -p "${BOOTSTRAP_WORK_DIR}" "${YASDB_MOUNT_HOME}" "${YASDB_DATA_PATH}"
  chown -R yashan:yashan "${YASDB_MOUNT_HOME}" "${BOOTSTRAP_WORK_DIR}" || true
  prepare_yasboot_permissions

  log "generating yasboot package for ${node_count} fixed-address nodes"
  # 2026-06-23 Reason: the earlier proof generated the yasboot package from the privileged shell before installing and deploying; Purpose: avoid image-specific permission differences during package se gen while keeping deploy under the database user.
  # 2026-06-23 Reason: live primary pods reported permission denied through the bin/yasboot symlink while standby direct execution was valid; Purpose: call the real yasboot binary path and log its permissions before orchestration.
  # Contract: this command is the fixed-address equivalent of `yasboot package se gen`.
  # Time: 2026-06-23.
  ls -l "${YASBOOT_HOME}/bin/yasboot" "${YASBOOT_BIN}" || true
  (
    cd "${YASBOOT_HOME}"
    "${YASBOOT_BIN}" package se gen \
      -c "${YASDB_HA_CLUSTER_NAME}" \
      -u yashan \
      -N \
      --ip "${YASDB_HA_NODE_IP_LIST}" \
      --port "${YASHANDB_SSHD_PORT}" \
      -i "${YASDB_MOUNT_HOME}" \
      --data-path "${YASDB_DATA_PATH}" \
      --node "${node_count}" \
      --begin-port "${YASDB_HA_DB_PORT}" \
      -f \
      -o "${BOOTSTRAP_PACKAGE_DIR}"
  )

  log "installing yasboot package"
  # 2026-06-23 Reason: local validation needs the exact yasboot package install contract visible in the script; Purpose: keep the empty-PVC bootstrap path auditable for PR review.
  # 2026-06-23 Reason: live package install run as root looked for /root/.ssh/id_rsa while yasboot hosts target the yashan user; Purpose: run remote SSH install from the database user with its bundled SSH key.
  # Time: 2026-06-23.
  su -s /bin/bash - yashan -c "cd '${YASBOOT_HOME}' && '${YASBOOT_BIN}' package install -t '${HOSTS_TOML}' --disable -f"

  log "deploying YashanDB HA cluster"
  # 2026-06-23 Reason: live validation showed su-based yasboot execution can fail before package generation in the KubeBlocks pod context; Purpose: run the yasboot orchestration from the privileged bootstrap shell while the generated hosts still target the yashan database user.
  # 2026-06-23 Reason: package install must use the yashan SSH identity; Purpose: keep cluster deploy on the same authenticated yasboot user path.
  # Contract: this command is the fixed-address equivalent of `yasboot cluster deploy`.
  # Time: 2026-06-23.
  su -s /bin/bash - yashan -c "cd '${YASBOOT_HOME}' && '${YASBOOT_BIN}' cluster deploy -t '${CLUSTER_TOML}' -p '${YASDB_PASSWORD}' --disable"

  chown -R yashan:yashan "${YASDB_MOUNT_HOME}" || true
  write_yasboot_env || true
  write_probe_env || true

  touch "${YASDB_FIXED_HA_BOOTSTRAP_DONE}"
}

keep_container_alive() {
  log "bootstrap path completed; keeping container alive for KubeBlocks probes"
  tail -F /dev/null
}

main() {
  start_sshd

  if already_bootstrapped; then
    log "PVC already bootstrapped"
    restore_bootstrapped_node
    keep_container_alive
  fi

  if is_primary_node; then
    wait_for_all_peers
    run_yasboot_primary_bootstrap
  else
    wait_for_local_deploy 900
  fi

  keep_container_alive
}

main "$@"
