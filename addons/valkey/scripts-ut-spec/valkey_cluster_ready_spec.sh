# shellcheck shell=sh
# shellcheck disable=SC2034

Describe "valkey-cluster-ready.sh"
  ready_script="../scripts/valkey-cluster-ready.sh"

  setup_ready() {
    ready_tmp=$(mktemp -d)
    ready_bin="${ready_tmp}/bin"
    mkdir -p "${ready_bin}" "${ready_tmp}/data"
    cat > "${ready_bin}/valkey-cli" <<'STUB'
#!/bin/sh
case "$*" in
  *PING*) printf '%s\n' "${FAKE_PING:-PONG}" ;;
  *"CLUSTER INFO"*)
    cluster_state="${FAKE_CLUSTER_STATE:-ok}"
    if [ -n "${FAKE_INFO_COUNTER_FILE:-}" ]; then
      count=$(cat "${FAKE_INFO_COUNTER_FILE}" 2>/dev/null || printf '0\n')
      count=$((count + 1))
      printf '%s\n' "${count}" > "${FAKE_INFO_COUNTER_FILE}"
      if [ "${count}" -gt 1 ]; then
        cluster_state="${FAKE_SECOND_CLUSTER_STATE:-${cluster_state}}"
      fi
    fi
    printf 'cluster_state:%s\n' "${cluster_state}"
    printf 'cluster_slots_assigned:%s\n' "${FAKE_ASSIGNED:-16384}"
    printf 'cluster_slots_ok:%s\n' "${FAKE_OK:-16384}"
    printf 'cluster_slots_pfail:%s\n' "${FAKE_PFAIL:-0}"
    printf 'cluster_slots_fail:%s\n' "${FAKE_FAIL:-0}"
    ;;
  *"CLUSTER NODES"*)
    if [ -n "${FAKE_CLUSTER_NODES:-}" ]; then
      printf '%b\n' "${FAKE_CLUSTER_NODES}"
    else
      printf '%s\n' \
        "master-id 10.0.0.1:6379@16379 master - 0 0 1 connected 0-16383" \
        "self-id 10.0.0.2:6379@16379 myself,slave master-id 0 0 1 connected"
    fi
    ;;
esac
STUB
    chmod +x "${ready_bin}/valkey-cli"
  }
  cleanup_ready() { rm -rf "${ready_tmp}"; }
  Before "setup_ready"
  After "cleanup_ready"

  run_ready() {
    PATH="${ready_bin}:${PATH}" VALKEY_DATA_DIR="${ready_tmp}/data" \
      sh "${ready_script}"
  }

  It "commits readiness for a joined replica when the marker is absent"
    When call run_ready
    The status should be success
    The contents of file "${ready_tmp}/data/.kb-valkey-cluster-formed" should equal "formed"
  End

  It "rechecks cluster health before committing a recovered marker"
    export FAKE_INFO_COUNTER_FILE="${ready_tmp}/info-count"
    export FAKE_SECOND_CLUSTER_STATE=fail
    When call run_ready
    The status should be failure
    The contents of file "${ready_tmp}/info-count" should equal "2"
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "keeps an unjoined slotless master out of readiness"
    export FAKE_CLUSTER_NODES="self-id 10.0.0.2:6379@16379 myself,master - 0 0 1 connected"
    When call run_ready
    The status should be failure
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "keeps an orphan replica out of readiness"
    export FAKE_CLUSTER_NODES="self-id 10.0.0.2:6379@16379 myself,slave missing-id 0 0 1 connected"
    When call run_ready
    The status should be failure
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "keeps a disconnected joined replica out of readiness"
    export FAKE_CLUSTER_NODES="master-id 10.0.0.1:6379@16379 master - 0 0 1 connected 0-16383\\nself-id 10.0.0.2:6379@16379 myself,slave master-id 0 0 1 disconnected"
    When call run_ready
    The status should be failure
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "keeps a failed joined replica out of readiness"
    export FAKE_CLUSTER_NODES="master-id 10.0.0.1:6379@16379 master - 0 0 1 connected 0-16383\\nself-id 10.0.0.2:6379@16379 myself,slave,fail master-id 0 0 1 connected"
    When call run_ready
    The status should be failure
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "keeps a replica whose parent owns no slots out of readiness"
    export FAKE_CLUSTER_NODES="master-id 10.0.0.1:6379@16379 master - 0 0 1 connected\\nself-id 10.0.0.2:6379@16379 myself,slave master-id 0 0 1 connected"
    When call run_ready
    The status should be failure
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "commits readiness for a connected slot-owning master"
    export FAKE_CLUSTER_NODES="self-id 10.0.0.2:6379@16379 myself,master - 0 0 1 connected 0-16383"
    When call run_ready
    The status should be success
    The contents of file "${ready_tmp}/data/.kb-valkey-cluster-formed" should equal "formed"
  End

  It "fails closed when the marker cannot be committed"
    chmod 0555 "${ready_tmp}/data"
    When call run_ready
    The status should be failure
    The stderr should be present
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should not be exist
  End

  It "requires complete healthy slots after formation"
    printf 'formed\n' > "${ready_tmp}/data/.kb-valkey-cluster-formed"
    export FAKE_CLUSTER_STATE=fail
    When call run_ready
    The status should be failure
  End

  It "accepts a formed cluster only with state ok and all slot counters healthy"
    printf 'formed\n' > "${ready_tmp}/data/.kb-valkey-cluster-formed"
    When call run_ready
    The status should be success
  End

  It "rejects a formed cluster with incomplete slot coverage"
    printf 'formed\n' > "${ready_tmp}/data/.kb-valkey-cluster-formed"
    export FAKE_OK=16383
    When call run_ready
    The status should be failure
  End

  It "rejects an empty or corrupt formation marker"
    : > "${ready_tmp}/data/.kb-valkey-cluster-formed"
    When call run_ready
    The status should be failure
    The contents of file "${ready_tmp}/data/.kb-valkey-cluster-formed" should equal ""
  End

  It "rejects a dangling formation-marker symlink"
    ln -s "${ready_tmp}/missing" "${ready_tmp}/data/.kb-valkey-cluster-formed"
    When call run_ready
    The status should be failure
    The path "${ready_tmp}/data/.kb-valkey-cluster-formed" should be symlink
  End
End
