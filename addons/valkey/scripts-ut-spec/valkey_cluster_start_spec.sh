# shellcheck shell=bash
# shellcheck disable=SC2034

# Phase A contract + behavioral tests for Valkey Cluster mode
# (issue #3021): config template contract, start-script fail-fast,
# announce trio, ACL materialization. Cluster formation is phase B.

Describe "Valkey cluster config template contract"
  cluster_tpl="../config/valkey-cluster-config.tpl"

  It "enables cluster mode with nodes.conf on the data volume"
    When call grep -E "^cluster-enabled yes|^cluster-config-file /data/nodes.conf" "${cluster_tpl}"
    The status should be success
    The stdout should include "cluster-enabled yes"
    The stdout should include "cluster-config-file /data/nodes.conf"
  End

  It "requires full slot coverage (fail loudly on missing slots)"
    When call grep -E "^cluster-require-full-coverage yes" "${cluster_tpl}"
    The status should be success
    The stdout should include "cluster-require-full-coverage"
  End

  It "carries no replicaof directive (cluster manages intra-shard replication)"
    When call grep -iE "^replicaof|^slaveof" "${cluster_tpl}"
    The status should be failure
  End

  It "keeps the database-safe eviction default (noeviction)"
    When call grep -E "^maxmemory-policy noeviction$" "${cluster_tpl}"
    The status should be success
    The stdout should include "noeviction"
  End
End

Describe "valkey-cluster-server-start.sh behavior"
  Include ../scripts/valkey-cluster-server-start.sh

  setup_env() {
    start_tmp=$(mktemp -d "${TMPDIR:-/tmp}/valkey-cluster-start.XXXXXX")
    start_tmp=$(cd -P "${start_tmp}" && pwd -P)
    export CURRENT_POD_NAME="vk-shard-a1x-0"
    export CURRENT_POD_IP="10.0.0.11"
    export CURRENT_SHARD_POD_FQDN_LIST="vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local,vk-shard-a1x-1.vk-shard-a1x-headless.ns.svc.cluster.local"
    export SERVICE_PORT="6379"
    export VALKEY_DATA_DIR="${start_tmp}/data"
    mkdir -p "${VALKEY_DATA_DIR}"
    unset CLUSTER_BUS_PORT VALKEY_DEFAULT_PASSWORD VALKEY_APPEND_DIRNAME VALKEY_APPEND_FILENAME
  }
  cleanup() {
    rm -rf "${start_tmp:-}"
    unset CURRENT_POD_NAME CURRENT_POD_IP CURRENT_SHARD_POD_FQDN_LIST SERVICE_PORT CLUSTER_BUS_PORT VALKEY_DEFAULT_PASSWORD VALKEY_DATA_DIR VALKEY_APPEND_DIRNAME VALKEY_APPEND_FILENAME
  }
  Before "setup_env"
  After "cleanup"

  Describe "validate_required_env()"
    It "fails fast listing every missing required variable"
      unset CURRENT_POD_IP CURRENT_SHARD_POD_FQDN_LIST VALKEY_DATA_DIR
      When call validate_required_env
      The status should be failure
      The stderr should include "CURRENT_POD_IP"
      The stderr should include "CURRENT_SHARD_POD_FQDN_LIST"
      The stderr should include "VALKEY_DATA_DIR"
      The stderr should include "refusing to start"
    End

    It "rejects a non-numeric SERVICE_PORT"
      export SERVICE_PORT="not-a-port"
      When call validate_required_env
      The status should be failure
      The stderr should include "SERVICE_PORT must be an integer in 1..65535"
    End

    It "passes with the full contract inputs"
      When call validate_required_env
      The status should be success
    End

    It "rejects a data directory that could make offline cleanup escape its volume"
      export VALKEY_DATA_DIR="/"
      When call validate_required_env
      The status should be failure
      The stderr should include "must not be the filesystem root"
    End

    It "rejects dot segments in the destructive data path"
      mkdir -p "${start_tmp}/other"
      export VALKEY_DATA_DIR="${start_tmp}/data/../other"
      When call validate_required_env
      The status should be failure
      The stderr should include "canonical path"
    End

    It "rejects a symlinked destructive data path"
      mkdir -p "${start_tmp}/real-data"
      ln -s "${start_tmp}/real-data" "${start_tmp}/linked-data"
      export VALKEY_DATA_DIR="${start_tmp}/linked-data"
      When call validate_required_env
      The status should be failure
      The stderr should include "canonical path"
    End

    It "rejects SERVICE_PORT=0 (out of 1..65535)"
      export SERVICE_PORT="0"
      When call validate_required_env
      The status should be failure
      The stderr should include "must be an integer in 1..65535"
    End

    It "rejects a non-numeric CLUSTER_BUS_PORT"
      export CLUSTER_BUS_PORT="abc"
      When call validate_required_env
      The status should be failure
      The stderr should include "CLUSTER_BUS_PORT must be an integer in 1..65535"
    End

    It "rejects CLUSTER_BUS_PORT above 65535"
      export CLUSTER_BUS_PORT="70000"
      When call validate_required_env
      The status should be failure
      The stderr should include "1..65535"
    End
  End


  Describe "prepare_restored_replica_offline()"
    seed_restored_archive() {
      printf 'snapshot\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      digest=$(sha256sum "${VALKEY_DATA_DIR}/dump.rdb" | awk '{print $1}')
      printf 'source_shards=3\nshard_master_id=source-id\nshard_slot_ranges=0-5460\nrdb_sha256=%s\n' "${digest}" \
        > "${VALKEY_DATA_DIR}/cluster-meta"
      meta_digest=$(sha256sum "${VALKEY_DATA_DIR}/cluster-meta" | awk '{print $1}')
      printf 'phase=prepared\nmeta_sha256=%s\n' "${meta_digest}" \
        > "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
      mkdir -p "${VALKEY_DATA_DIR}/appendonlydir"
      cp "${VALKEY_DATA_DIR}/dump.rdb" "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.1.base.rdb"
      : > "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.1.incr.aof"
      printf 'file appendonly.aof.1.base.rdb seq 1 type b\nfile appendonly.aof.1.incr.aof seq 1 type i\n' \
        > "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.manifest"
    }

    It "preserves the restored payload on the shard first pod"
      seed_restored_archive
      When call prepare_restored_replica_offline
      The status should be success
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should be exist
      The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" should not be exist
    End

    It "refuses a prepared restore when cluster-meta is missing"
      printf 'snapshot\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      printf 'phase=prepared\nmeta_sha256=%064d\n' 0 \
        > "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "lacks cluster-meta"
      The stderr should include "refusing ordinary startup"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
    End

    It "allows a formed restore restart without cluster-meta"
      printf 'replicated\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      printf 'phase=formed\nmeta_sha256=%064d\n' 0 \
        > "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
      When call prepare_restored_replica_offline
      The status should be success
      The contents of file "${VALKEY_DATA_DIR}/dump.rdb" should include "replicated"
    End

    It "refuses a symlinked formed restore state without cluster-meta"
      outside_state="${SHELLSPEC_TMPBASE}/outside-restore-state"
      printf 'phase=formed\nmeta_sha256=%064d\n' 0 > "${outside_state}"
      ln -s "${outside_state}" "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "not a safe regular file"
    End


    It "does not classify an ordinary data-bearing restart as restore"
      printf 'ordinary\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      When call prepare_restored_replica_offline
      The status should be success
      The contents of file "${VALKEY_DATA_DIR}/dump.rdb" should include "ordinary"
    End

    It "discards a verified non-first payload before server start"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      When call prepare_restored_replica_offline
      The status should be success
      The stdout should include "Prepared restored replica"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should not be exist
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should not be exist
      The file "${VALKEY_DATA_DIR}/cluster-meta" should be exist
      The contents of file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" should include "pod=vk-shard-a1x-1"
      The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare" should not be exist
    End

    It "fails closed before deletion when the archive digest differs"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      printf 'tampered\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "does not match cluster-meta"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should be exist
    End

    It "refuses a symlinked dump.rdb before destructive cleanup"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      mv "${VALKEY_DATA_DIR}/dump.rdb" "${start_tmp}/outside-rdb"
      ln -s "${start_tmp}/outside-rdb" "${VALKEY_DATA_DIR}/dump.rdb"

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "dump.rdb is not a safe regular file"
      The file "${start_tmp}/outside-rdb" should be exist
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should be exist
    End

    It "rejects an unsafe AOF directory contract before deletion"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      export VALKEY_APPEND_DIRNAME=".."
      seed_restored_archive
      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "unsafe restored replica AOF directory"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should be exist
    End

    It "rejects an explicitly empty AOF directory contract before deletion"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      export VALKEY_APPEND_DIRNAME=""
      seed_restored_archive

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "unsafe restored replica AOF directory"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
    End

    It "rejects an explicitly empty AOF filename contract before deletion"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      export VALKEY_APPEND_FILENAME=""
      seed_restored_archive

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "unsafe restored replica AOF path contract"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
    End


    It "refuses a symlinked AOF directory without touching its target"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      mv "${VALKEY_DATA_DIR}/appendonlydir" "${start_tmp}/outside-aof"
      ln -s "${start_tmp}/outside-aof" "${VALKEY_DATA_DIR}/appendonlydir"
      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "multipart AOF is not the pristine restore seed"
      The file "${start_tmp}/outside-aof/appendonly.aof.1.base.rdb" should be exist
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
    End

    It "resumes an authorized deletion interrupted before the prepared marker"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" \
        > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare"
      rm -f "${VALKEY_DATA_DIR}/dump.rdb"
      When call prepare_restored_replica_offline
      The status should be success
      The stdout should include "Prepared restored replica"
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should not be exist
      The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" should be exist
      The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare" should not be exist
    End

    It "refuses a symlinked prepare marker before destructive cleanup"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      outside_marker="${start_tmp}/outside-prepare-marker"
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" > "${outside_marker}"
      ln -s "${outside_marker}" \
        "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare"

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "not a safe regular file"
      The file "${VALKEY_DATA_DIR}/dump.rdb" should be exist
      The dir "${VALKEY_DATA_DIR}/appendonlydir" should be exist
    End

    It "never clears replicated data after the prepared marker exists"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" \
        > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
      printf 'replicated-later\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      printf 'replicated-aof\n' > "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.1.incr.aof"
      When call prepare_restored_replica_offline
      The status should be success
      The contents of file "${VALKEY_DATA_DIR}/dump.rdb" should include "replicated-later"
      The contents of file "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.1.incr.aof" should include "replicated-aof"
    End

    It "refuses a symlinked prepared marker without clearing replicated data"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      outside_marker="${start_tmp}/outside-prepared-marker"
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" > "${outside_marker}"
      ln -s "${outside_marker}" \
        "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
      printf 'replicated-later\n' > "${VALKEY_DATA_DIR}/dump.rdb"

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "not a safe regular file"
      The contents of file "${VALKEY_DATA_DIR}/dump.rdb" should include "replicated-later"
    End

    It "refuses a valid prepared marker that coexists with a symlinked prepare marker"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" \
        > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
      outside_marker="${start_tmp}/outside-prepare-marker"
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" > "${outside_marker}"
      ln -s "${outside_marker}" \
        "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare"

      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "offline prepare marker is not a safe regular file"
    End


    It "fails closed when the restore metadata changes after offline authorization"
      export CURRENT_POD_NAME="vk-shard-a1x-1"
      seed_restored_archive
      printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s\n' \
        "${digest}" "${meta_digest}" "${CURRENT_POD_NAME}" \
        > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
      printf '# changed after authorization\n' >> "${VALKEY_DATA_DIR}/cluster-meta"
      printf 'replicated-later\n' > "${VALKEY_DATA_DIR}/dump.rdb"
      When call prepare_restored_replica_offline
      The status should be failure
      The stderr should include "restore state does not match cluster-meta"
      The contents of file "${VALKEY_DATA_DIR}/dump.rdb" should include "replicated-later"
    End
  End

  Describe "resolve_self_fqdn()"
    It "resolves this pod's FQDN from the KB-provided shard list"
      When call resolve_self_fqdn
      The status should be success
      The stdout should equal "vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local"
    End

    It "fails when the pod is absent from the shard list (no guessing)"
      export CURRENT_POD_NAME="vk-shard-zzz-9"
      When call resolve_self_fqdn
      The status should be failure
      The stderr should include "not found in CURRENT_SHARD_POD_FQDN_LIST"
    End
  End

  Describe "build_cluster_conf()"
    # These specs run the REAL production function (via VALKEY_CONF_DIR /
    # VALKEY_ACL_FILE overrides) — never an inline copy. A sandboxed
    # re-implementation is a tautology: deleting the announce trio from the
    # production function would not fail it (fresh-eyes review finding).
    conf_setup() {
      tmpdir=$(mktemp -d)
      export VALKEY_CONF_DIR="${tmpdir}/etc-valkey"
      export VALKEY_ACL_FILE="${tmpdir}/data/users.acl"
      mkdir -p "${tmpdir}/data"
    }
    conf_cleanup() {
      rm -rf "${tmpdir}"
      unset VALKEY_CONF_DIR VALKEY_ACL_FILE
    }
    Before "conf_setup"
    After "conf_cleanup"

    It "renders the announce trio and derives the bus port from SERVICE_PORT"
      conf_file=$(build_cluster_conf "vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local")
      When call cat "${conf_file}"
      The status should be success
      The stdout should include "include /etc/conf/valkey.conf"
      The stdout should include "port 6379"
      The stdout should include "cluster-port 16379"
      The stdout should include "cluster-announce-ip 10.0.0.11"
      The stdout should include "cluster-announce-hostname vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local"
      The stdout should include "cluster-preferred-endpoint-type hostname"
    End

    It "opens protected mode only when no default password is set"
      unset VALKEY_DEFAULT_PASSWORD
      conf_file=$(build_cluster_conf "vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local")
      When call cat "${conf_file}"
      The status should be success
      The stdout should include "protected-mode no"
    End

    It "materializes the per-node ACL file and master auth when a password is set"
      export VALKEY_DEFAULT_PASSWORD="s3cret"
      conf_file=$(build_cluster_conf "vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local")
      When call cat "${conf_file}"
      The status should be success
      The stdout should include "aclfile ${VALKEY_ACL_FILE}"
      The stdout should include "masteruser default"
      The stdout should not include "protected-mode no"
      The file "${VALKEY_ACL_FILE}" should be exist
      The contents of file "${VALKEY_ACL_FILE}" should include "user default on #"
    End
  End
End

Describe "Valkey cluster template contracts"
  cmpd="../templates/cmpd-valkey-cluster.yaml"
  shardingdef="../templates/shardingdefinition.yaml"
  clusterdef="../templates/clusterdefinition.yaml"
  start_script="../scripts/valkey-cluster-server-start.sh"

  It "declares the v1 shard bounds 3..32"
    When call grep -E "minShards: 3|maxShards: 32" "${shardingdef}"
    The status should be success
    The stdout should include "minShards: 3"
    The stdout should include "maxShards: 32"
  End

  It "adds the cluster topology without touching the default (replication)"
    When call grep -E "name: cluster|shardingDef: valkey-cluster" "${clusterdef}"
    The status should be success
    The stdout should include "shardingDef: valkey-cluster"
  End

  It "carries no hardcoded ports in the cluster start script"
    # Ports must come from SERVICE_PORT / CLUSTER_BUS_PORT vars.
    When call grep -E "(^|[^0-9])(6379|16379)([^0-9]|$)" "${start_script}"
    The status should be failure
  End

  It "provides the persistent data directory required by offline restore preparation"
    When call grep -c "name: VALKEY_DATA_DIR" "${cmpd}"
    The status should be success
    The stdout should equal "1"
  End

  It "uses same-directory mktemp files instead of predictable PID temp paths"
    When call grep -E '\.tmp\.\$\$' "${start_script}" ../dataprotection/restore.sh ../scripts/valkey-cluster-manage.sh
    The status should be failure
  End

  restored_prepare_precedes_server_start() {
    awk '
      /^prepare_restored_replica_offline \|\| exit 1$/ { prepare = NR }
      /^conf_file=\$\(build_cluster_conf / { config = NR }
      /^start_cluster_server / { start = NR }
      END { exit !(prepare > 0 && prepare < config && config < start) }
    ' "$1"
  }

  It "prepares restored replicas before config rendering and server exec"
    When call restored_prepare_precedes_server_start "${start_script}"
    The status should be success
  End

  It "wires postProvision preCondition at the action level (KB Action API shape)"
    # Live install first-blocker (kubeblocks-tests #583): 'precondition'
    # nested under exec is not a CRD field and fails addon install. The
    # correct shape is action-level 'preCondition', a SIBLING of exec —
    # same as the sentinel cmpd prior art.
    When call grep -c "^      preCondition: RuntimeReady" "${cmpd}"
    The status should be success
    The stdout should equal "1"
  End

  It "carries no exec-nested lowercase 'precondition:' anywhere in the cluster cmpd"
    When call grep -E "precondition:" "${cmpd}"
    The status should be failure
    The stdout should equal ""
  End

  # kbagent-executed actions do NOT inherit the runtime container's
  # downward-API env (r2 live first-blocker: manage script fail-fasted on
  # missing CURRENT_POD_NAME). Pod identity must be pinned on the ACTION
  # env itself — asserting the runtime container env is NOT sufficient.
  action_env_has_pod_name() {
    awk "/^    ${2}:/,/^      retryPolicy:/" "${1}" | grep -c "name: CURRENT_POD_NAME"
  }

  It "pins CURRENT_POD_NAME on the postProvision ACTION env (not just runtime)"
    When call action_env_has_pod_name "${cmpd}" "postProvision"
    The status should be success
    The stdout should equal "1"
  End

  It "pins CURRENT_POD_NAME on the shardRemove ACTION env (not just runtime)"
    When call action_env_has_pod_name "${shardingdef}" "shardRemove"
    The status should be success
    The stdout should equal "1"
  End

  It "declares shardRemove backed by the drain-then-prove manage script"
    # Shard scale is only legal WITH the slot-drain script (the
    # shardRemove-vs-preTerminate data-safety trap): the action and the
    # script must appear together.
    When call grep -E "shardRemove:|valkey-cluster-manage.sh --shard-remove" "${shardingdef}"
    The status should be success
    The stdout should include "shardRemove:"
    The stdout should include "--shard-remove"
  End
End
