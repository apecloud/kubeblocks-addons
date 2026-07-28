# shellcheck shell=bash
# shellcheck disable=SC2034

# Behavioral test for cluster-mode backup metadata (PR-D review gap):
# runs backup.sh against PATH-stubbed valkey-cli/datasafed and proves
# (a) cluster-meta lands INSIDE the archive with master-line slot ranges
# and shard identity, and (b) cluster-meta does NOT remain in DATA_DIR.

Describe "backup.sh cluster-mode metadata (behavioral)"
  setup_harness() {
    unset FAKE_CLUSTER_RANGE FAKE_CLUSTER_RANGE_AFTER \
      FAKE_REMOTE_RANGE FAKE_REMOTE_RANGE_AFTER \
      FAKE_CLUSTER_INFO_FAIL FAKE_CLUSTER_ENABLED \
      FAKE_CURRENT_EPOCH FAKE_CURRENT_EPOCH_AFTER \
      FAKE_MY_EPOCH FAKE_MY_EPOCH_AFTER
    workdir=$(mktemp -d)
    data_dir="${workdir}/data"
    bindir="${workdir}/bin"
    mkdir -p "${data_dir}" "${bindir}"

    # Stub valkey-cli: BGSAVE flow + a primary target's authoritative view.
    cat > "${bindir}/valkey-cli" <<'STUB'
#!/bin/bash
args="$*"
case "${args}" in
  *"INFO persistence"*)
    printf 'rdb_bgsave_in_progress:0\nrdb_last_bgsave_status:ok\n'; exit 0 ;;
  *LASTSAVE*)
    # advance on every call so the post-BGSAVE read exceeds the baseline
    n=$(cat "${LASTSAVE_COUNTER:-/tmp/ls-counter}" 2>/dev/null || echo 100)
    n=$((n + 1)); echo "${n}" > "${LASTSAVE_COUNTER:-/tmp/ls-counter}"
    echo "${n}"; exit 0 ;;
  *BGSAVE*)             echo "Background saving started"; exit 0 ;;
  *"INFO cluster"*)
    [ "${FAKE_CLUSTER_INFO_FAIL:-0}" = "1" ] && exit 1
    printf 'cluster_enabled:%s\n' "${FAKE_CLUSTER_ENABLED:-1}"; exit 0 ;;
  *"CLUSTER INFO"*)
    count=$(cat "${INFO_COUNTER:-/tmp/info-counter}" 2>/dev/null || echo 0)
    count=$((count + 1)); echo "${count}" > "${INFO_COUNTER:-/tmp/info-counter}"
    current_epoch="${FAKE_CURRENT_EPOCH:-8}"
    my_epoch="${FAKE_MY_EPOCH:-5}"
    [ "${count}" -gt 1 ] && current_epoch="${FAKE_CURRENT_EPOCH_AFTER:-${current_epoch}}"
    [ "${count}" -gt 1 ] && my_epoch="${FAKE_MY_EPOCH_AFTER:-${my_epoch}}"
    printf 'cluster_state:ok\ncluster_slots_assigned:16384\ncluster_slots_ok:16384\ncluster_slots_pfail:0\ncluster_slots_fail:0\ncluster_current_epoch:%s\ncluster_my_epoch:%s\n' "${current_epoch}" "${my_epoch}"
    exit 0 ;;
  *"CLUSTER NODES"*)
    count=$(cat "${NODES_COUNTER:-/tmp/nodes-counter}" 2>/dev/null || echo 0)
    count=$((count + 1)); echo "${count}" > "${NODES_COUNTER:-/tmp/nodes-counter}"
    range="${FAKE_CLUSTER_RANGE:-0-5460}"
    [ "${count}" -gt 1 ] && range="${FAKE_CLUSTER_RANGE_AFTER:-${range}}"
    remote_range="${FAKE_REMOTE_RANGE:-5461-10922}"
    [ "${count}" -gt 1 ] && remote_range="${FAKE_REMOTE_RANGE_AFTER:-${remote_range}}"
    printf 'mid001 10.0.0.1:6379@16379 myself,master - 0 0 5 connected %s\n' "${range}"
    printf 'sid002 10.0.0.2:6379@16379 slave mid001 0 0 5 connected\n'
    printf 'mid003 10.0.0.3:6379@16379 master - 0 0 6 connected %s\n' "${remote_range}"
    printf 'mid004 10.0.0.4:6379@16379 master - 0 0 7 connected 10923-16383\n'
    exit 0 ;;
  *PING*)               echo PONG; exit 0 ;;
esac
exit 0
STUB
    # Stub datasafed: capture the tar member list ONLY for the archive
    # push (a later 'datasafed stat' call must not truncate the capture).
    cat > "${bindir}/datasafed" <<STUB
#!/bin/bash
case "\$1" in
  push)
    if [ "\$4" = "-" ] || [ "\$2" = "-" ] || [ "\$3" = "-" ]; then
      tar -tf - > "${workdir}/pushed-files.txt" 2>/dev/null || cat > /dev/null
    else
      cat > /dev/null 2>&1 || true
    fi ;;
  stat) echo "TotalSize 1234" ;;
esac
exit 0
STUB
    chmod +x "${bindir}"/*

    # minimal backup preconditions
    printf 'x' > "${data_dir}/dump.rdb.seed" # ensure dir non-empty
    printf 'rdbdata' > "${data_dir}/dump.rdb"
    printf 'user default on\n' > "${data_dir}/users.acl"
  }
  teardown_harness() { rm -rf "${workdir}"; }
  Before "setup_harness"
  After "teardown_harness"

  run_backup() {
    (
      export PATH="${bindir}:${PATH}"
      export DATA_DIR="${data_dir}"
      export DP_DB_HOST=10.0.0.1 DP_DB_PORT=6379 DP_BACKUP_NAME=bk-test
      export LASTSAVE_COUNTER="${workdir}/ls-counter"
      export NODES_COUNTER="${workdir}/nodes-counter"
      export INFO_COUNTER="${workdir}/info-counter"
      export DP_BACKUP_BASE_PATH="${workdir}" DP_BACKUP_INFO_FILE="${workdir}/info.json"
      unset DP_DB_PASSWORD SENTINEL_POD_FQDN_LIST
      bash ../dataprotection/backup.sh
    )
  }

  It "embeds cluster-meta with master-line ranges and cleans DATA_DIR"
    When call run_backup
    The status should be success
    The stdout should include "embedded cluster-meta (source_shards=3)"
    # tar -v member list goes to stderr (archive is on stdout); the
    # substring matches both BSD ("a ./cluster-meta") and GNU ("./cluster-meta")
    The stderr should include "cluster-meta"
    The file "${workdir}/pushed-files.txt" should be exist
    The contents of file "${workdir}/pushed-files.txt" should include "cluster-meta"
    The contents of file "${workdir}/pushed-files.txt" should include "dump.rdb"
    # metadata must not remain on the live data volume
    The file "${data_dir}/cluster-meta" should not be exist
  End

  It "records the target primary's authoritative slot ranges"
    # re-run capturing the meta content before tar consumes it: intercept
    # via a datasafed stub that also extracts the archive.
    cat > "${bindir}/datasafed" <<STUB
#!/bin/bash
case "\$1" in
  push)
    mkdir -p "${workdir}/extracted"
    tar -xf - -C "${workdir}/extracted" 2>/dev/null || cat > /dev/null ;;
  stat) echo "TotalSize 1234" ;;
esac
exit 0
STUB
    chmod +x "${bindir}/datasafed"
    When call run_backup
    The status should be success
    The stdout should include "embedded cluster-meta (source_shards=3)"
    The stderr should include "cluster-meta"
    The contents of file "${workdir}/extracted/cluster-meta" should include "source_shards=3"
    The contents of file "${workdir}/extracted/cluster-meta" should include "shard_master_id=mid001"
    The contents of file "${workdir}/extracted/cluster-meta" should include "shard_slot_ranges=0-5460"
    The contents of file "${workdir}/extracted/cluster-meta" should include "rdb_sha256="
  End

  It "fails when the primary topology changes during the BGSAVE window"
    export FAKE_CLUSTER_RANGE_AFTER='0-5459'
    export FAKE_REMOTE_RANGE_AFTER='5460-10922'
    When call run_backup
    The status should be failure
    The stdout should include "INFO: Triggering BGSAVE"
    The stderr should include "topology changed during BGSAVE"
    The file "${data_dir}/cluster-meta" should not be exist
  End

  It "fails when the cluster epoch changes during the BGSAVE window"
    export FAKE_CURRENT_EPOCH_AFTER=9
    When call run_backup
    The status should be failure
    The stdout should include "INFO: Triggering BGSAVE"
    The stderr should include "topology changed during BGSAVE"
    The file "${data_dir}/cluster-meta" should not be exist
  End


  It "fails before archiving when the engine view contains migration markers"
    export FAKE_CLUSTER_RANGE='0-5460 [123->-peer]'
    When call run_backup
    The status should be failure
    The stdout should not include "INFO: Archiving consistent snapshot artifacts..."
    The stderr should include "slot ownership is incomplete"
    The file "${data_dir}/cluster-meta" should not be exist
  End

  It "fails before BGSAVE when any master has migrating slots"
    export FAKE_REMOTE_RANGE='5461-10922 [123->-peer]'
    When call run_backup
    The status should be failure
    The stdout should not include "INFO: Triggering BGSAVE"
    The stderr should include "slot ownership is incomplete"
  End

  It "fails closed when cluster mode cannot be determined"
    export FAKE_CLUSTER_INFO_FAIL=1
    When call run_backup
    The status should be failure
    The stdout should not include "INFO: Triggering BGSAVE"
    The stderr should include "cannot determine whether cluster mode is enabled"
  End
End
