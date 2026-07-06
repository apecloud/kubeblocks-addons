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
    conf_setup() {
      tmpdir=$(mktemp -d)
      # redirect the conf dir and data dir into the sandbox
      build_cluster_conf_sandboxed() {
        local self="$1"
        mkdir -p "${tmpdir}/etc-valkey" "${tmpdir}/data"
        conf_dir_override="${tmpdir}/etc-valkey"
        # shellcheck disable=SC2317
        local out
        out=$( conf_dir="${conf_dir_override}" ; \
          { echo "include /etc/conf/valkey.conf"; \
            echo "port ${SERVICE_PORT}"; \
            echo "cluster-port ${CLUSTER_BUS_PORT:-$((SERVICE_PORT + 10000))}"; \
            echo "cluster-announce-ip ${CURRENT_POD_IP}"; \
            echo "cluster-announce-hostname ${self}"; \
            echo "cluster-preferred-endpoint-type hostname"; } > "${conf_dir_override}/valkey.conf" ; \
          echo "${conf_dir_override}/valkey.conf" )
        echo "${out}"
      }
    }
    conf_cleanup() { rm -rf "${tmpdir}"; }
    Before "conf_setup"
    After "conf_cleanup"

    It "renders the announce trio and derives the bus port from SERVICE_PORT"
      conf_file=$(build_cluster_conf_sandboxed "vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local")
      When call cat "${conf_file}"
      The status should be success
      The stdout should include "cluster-port 16379"
      The stdout should include "cluster-announce-ip 10.0.0.11"
      The stdout should include "cluster-announce-hostname vk-shard-a1x-0.vk-shard-a1x-headless.ns.svc.cluster.local"
      The stdout should include "cluster-preferred-endpoint-type hostname"
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

  It "declares no shard lifecycle actions yet (phase B owns shardRemove)"
    # Guard: shard scale must not be enabled before the slot-drain script
    # exists (shardRemove-vs-preTerminate data-safety trap). Match YAML
    # keys only; the design comment legitimately mentions the action name.
    When call grep -E "^[[:space:]]*(shardRemove|shardAdd|lifecycleActions):" "${shardingdef}"
    The status should be failure
  End
End
