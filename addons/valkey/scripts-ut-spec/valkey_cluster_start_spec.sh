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
    export CURRENT_POD_NAME="vk-shard-a1x-0"
    export CURRENT_POD_IP="10.0.0.11"
    export CURRENT_SHARD_POD_FQDN_LIST="vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local,vk-shard-a1x-1.vk-shard-a1x-headless.ns.svc.cluster.local"
    export SERVICE_PORT="6379"
    unset CLUSTER_BUS_PORT VALKEY_DEFAULT_PASSWORD
  }
  cleanup() {
    unset CURRENT_POD_NAME CURRENT_POD_IP CURRENT_SHARD_POD_FQDN_LIST SERVICE_PORT CLUSTER_BUS_PORT VALKEY_DEFAULT_PASSWORD
  }
  Before "setup_env"
  After "cleanup"

  Describe "validate_required_env()"
    It "fails fast listing every missing required variable"
      unset CURRENT_POD_IP CURRENT_SHARD_POD_FQDN_LIST
      When call validate_required_env
      The status should be failure
      The stderr should include "CURRENT_POD_IP"
      The stderr should include "CURRENT_SHARD_POD_FQDN_LIST"
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
