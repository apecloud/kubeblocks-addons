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
    printf 'cluster_state:%s\n' "${FAKE_CLUSTER_STATE:-ok}"
    printf 'cluster_slots_assigned:%s\n' "${FAKE_ASSIGNED:-16384}"
    printf 'cluster_slots_ok:%s\n' "${FAKE_OK:-16384}"
    printf 'cluster_slots_pfail:%s\n' "${FAKE_PFAIL:-0}"
    printf 'cluster_slots_fail:%s\n' "${FAKE_FAIL:-0}"
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

  It "allows PING-only readiness before the durable formation marker exists"
    When call run_ready
    The status should be success
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
  End

  It "rejects a dangling formation-marker symlink"
    ln -s "${ready_tmp}/missing" "${ready_tmp}/data/.kb-valkey-cluster-formed"
    When call run_ready
    The status should be failure
  End
End
