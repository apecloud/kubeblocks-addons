# shellcheck shell=bash

Describe "Redis Cluster shardAdd managed-operation worker"
  worker_path() {
    printf '%s/addons/redis/redis-cluster-scripts/redis-cluster-shardadd-worker.sh' "${SHELLSPEC_CWD:?}"
  }

  setup_worker() {
    fake_bin=$(mktemp -d -t redis-shardadd-bin-XXXXXX)
    fake_state=$(mktemp -t redis-shardadd-state-XXXXXX)
    fake_log=$(mktemp -t redis-shardadd-log-XXXXXX)
    rm -f "$fake_state"
    cp "${SHELLSPEC_CWD:?}/addons/redis/scripts-ut-spec/fixtures/redis_cluster_shardadd_worker_redis_cli.sh" "$fake_bin/redis-cli"
    chmod +x "$fake_bin/redis-cli"

    export PATH="$fake_bin:$PATH"
    export FAKE_STATE_FILE="$fake_state"
    export FAKE_REDIS_CLI_LOG="$fake_log"
    export REDIS_CLUSTER_ENDPOINT="host1:6379"
    export REDIS_TARGET_SHARD_COUNT="2"
    export REDIS_NEW_MASTER_IDS="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    export REDIS_DEFAULT_USER="default"
    export REDIS_COMMAND_TIMEOUT_SECONDS="5"
    export REDIS_COMMAND_KILL_GRACE_SECONDS="1"
  }
  Before 'setup_worker'

  cleanup_worker() {
    rm -rf "$fake_bin"
    rm -f "$fake_state" "$fake_log"
    unset FAKE_SCENARIO FAKE_STATE_FILE FAKE_REDIS_CLI_LOG FAKE_REDIS_MAJOR
    unset REDIS_CLUSTER_ENDPOINT REDIS_TARGET_SHARD_COUNT REDIS_NEW_MASTER_IDS
    unset REDIS_DEFAULT_USER REDIS_DEFAULT_PASSWORD
    unset REDIS_TLS_ENABLED REDIS_TLS_CA_FILE REDIS_TLS_CERT_FILE REDIS_TLS_KEY_FILE
    unset REDIS_COMMAND_TIMEOUT_SECONDS REDIS_COMMAND_KILL_GRACE_SECONDS
  }
  After 'cleanup_worker'

  run_worker() {
    bash "$(worker_path)"
  }

  It "fails closed before redis-cli when required lifecycle inputs are missing"
    unset REDIS_TARGET_SHARD_COUNT
    When call run_worker
    The status should be failure
    The stderr should include "missing REDIS_TARGET_SHARD_COUNT"
    The contents of file "$fake_log" should be blank
  End

  It "is a no-op when the requested topology is already converged"
    export FAKE_SCENARIO=stable
    When call run_worker
    The status should be success
    The output should include "already converged"
    The contents of file "$fake_log" should not include "--cluster rebalance"
    The contents of file "$fake_log" should include "-h host3"
  End

  It "rejects malformed or duplicate new-master IDs before redis-cli"
    export REDIS_NEW_MASTER_IDS="not-a-node-id"
    bash "$(worker_path)" 2>/dev/null && return 1
    export REDIS_NEW_MASTER_IDS="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb,bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    When call run_worker
    The status should be failure
    The stderr should include "duplicate Redis node IDs"
    The contents of file "$fake_log" should be blank
  End


  It "fails before mutation when a supplied new-master ID is absent"
    export FAKE_SCENARIO=missing_new
    When call run_worker
    The status should be failure
    The stderr should include "not unique healthy masters"
    The contents of file "$fake_log" should not include "--cluster rebalance"
  End

  It "fails before mutation when a supplied new-master ID is a replica"
    export FAKE_SCENARIO=replica_new
    When call run_worker
    The status should be failure
    The stderr should include "not unique healthy masters"
    The contents of file "$fake_log" should not include "--cluster rebalance"
  End

  It "runs one global rebalance for an empty new master and verifies convergence"
    export FAKE_SCENARIO=empty
    When call run_worker
    The status should be success
    The output should include "rebalance completed and topology converged"
    The contents of file "$fake_log" should include "--cluster rebalance"
    The contents of file "$fake_log" should include "--cluster-use-empty-masters"
  End

  It "fails closed when Redis nodes expose different slot-owner views"
    export FAKE_SCENARIO=inconsistent
    When call run_worker
    The status should be failure
    The stderr should include "Redis Cluster node views do not agree"
  End

  It "repairs an explicit open-slot state before the single rebalance"
    export FAKE_SCENARIO=partial_open
    When call run_worker
    The status should be success
    The output should include "rebalance completed and topology converged"
    The contents of file "$fake_log" should include "--cluster fix"
    The contents of file "$fake_log" should include "--cluster rebalance"
  End

  It "fails an interrupted rebalance and safely converges on retry"
    export FAKE_SCENARIO=interrupted
    bash "$(worker_path)" >/dev/null 2>&1 && return 1
    When call run_worker
    The status should be success
    The output should include "rebalance completed and topology converged"
    The contents of file "$fake_log" should include "--cluster fix"
  End


  It "bounds a stalled redis-cli command and reaps it"
    export FAKE_SCENARIO=hang
    export REDIS_COMMAND_TIMEOUT_SECONDS=1
    When call run_worker
    The status should be failure
    The stderr should include "redis-cli command timed out after 1 seconds"
    The contents of file "$fake_log" should include "terminated"
  End


  It "also bounds and reaps a stalled redis-cli version probe"
    export FAKE_SCENARIO=hang_version
    export REDIS_COMMAND_TIMEOUT_SECONDS=1
    When call run_worker
    The status should be failure
    The stderr should include "redis-cli version probe timed out after 1 seconds"
    The contents of file "$fake_log" should include "version-terminated"
  End

  It "does not mutate when cluster-check returns an unknown error"
    export FAKE_SCENARIO=unknown
    When call run_worker
    The status should be failure
    The stderr should include "unrecoverable error before rebalance"
    The contents of file "$fake_log" should not include "--cluster fix"
    The contents of file "$fake_log" should not include "--cluster rebalance"
  End

  It "uses one worker contract for Redis 5, 6, 7, and 8 without exposing the password"
    export FAKE_SCENARIO=stable
    export REDIS_DEFAULT_PASSWORD='worker-secret-value'
    for major in 5 6 7 8; do
      export FAKE_REDIS_MAJOR=$major
      bash "$(worker_path)" || return $?
    done
    When call grep -F 'worker-secret-value' "$fake_log"
    The status should be failure
  End


  It "requires readable TLS material and passes only file paths to redis-cli"
    export FAKE_SCENARIO=stable
    export REDIS_TLS_ENABLED=true
    export REDIS_TLS_CA_FILE="$fake_bin/ca.crt"
    export REDIS_TLS_CERT_FILE="$fake_bin/tls.crt"
    export REDIS_TLS_KEY_FILE="$fake_bin/tls.key"
    touch "$REDIS_TLS_CA_FILE" "$REDIS_TLS_CERT_FILE"
    bash "$(worker_path)" >/dev/null 2>&1 && return 1
    touch "$REDIS_TLS_KEY_FILE"
    When call run_worker
    The status should be success
    The output should include "already converged"
    The contents of file "$fake_log" should include "--tls"
    The contents of file "$fake_log" should include "$fake_bin/tls.key"
  End
End
