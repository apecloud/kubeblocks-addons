# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey cluster restore slot contract"
  Include ../scripts/valkey-cluster-manage.sh

  restore_env() {
    restore_tmp=$(mktemp -d "${TMPDIR:-/tmp}/valkey-cluster-restore.XXXXXX")
    restore_tmp=$(cd -P "${restore_tmp}" && pwd -P)
    restore_meta="${restore_tmp}/cluster-meta"
    cat > "${restore_meta}" <<'META'
source_shards=3
shard_master_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
shard_slot_ranges=0-5460
rdb_sha256=827eeab94f7421c651f6170d7d0e62cd4fad4594fb07faff4466acb01128ccd9
META
    meta_digest=$(sha256sum "${restore_meta}" | awk '{print $1}')
    printf 'phase=prepared\nmeta_sha256=%s\n' "${meta_digest}" \
      > "${restore_tmp}/.kb-cluster-restore-state"
    printf 'snapshot\n' > "${restore_tmp}/dump.rdb"
    mkdir -p "${restore_tmp}/appendonlydir"
    cp "${restore_tmp}/dump.rdb" "${restore_tmp}/appendonlydir/appendonly.aof.1.base.rdb"
    : > "${restore_tmp}/appendonlydir/appendonly.aof.1.incr.aof"
    printf 'file appendonly.aof.1.base.rdb seq 1 type b\nfile appendonly.aof.1.incr.aof seq 1 type i\n' \
      > "${restore_tmp}/appendonlydir/appendonly.aof.manifest"
    export VALKEY_DATA_DIR="${restore_tmp}"
    export CURRENT_POD_NAME="vk-shard-abc-0"
    export CURRENT_SHARD_COMPONENT_SHORT_NAME="shard-abc"
    export CURRENT_SHARD_POD_FQDN_LIST="vk-shard-abc-0.h,vk-shard-abc-1.h"
    export ALL_SHARDS_COMPONENT_SHORT_NAMES="shard-abc:shard-abc,shard-def:shard-def,shard-ghi:shard-ghi"
    export SERVICE_PORT=6379
    each_shard_fqdn_list() {
      printf 'SHARD_ABC vk-shard-abc-0.h,vk-shard-abc-1.h\n'
      printf 'SHARD_DEF vk-shard-def-0.h,vk-shard-def-1.h\n'
      printf 'SHARD_GHI vk-shard-ghi-0.h,vk-shard-ghi-1.h\n'
    }
    node_id_of() {
      case "$1" in
        vk-shard-abc-0.h) echo id-abc ;;
        vk-shard-def-0.h) echo id-def ;;
        vk-shard-ghi-0.h) echo id-ghi ;;
      esac
    }
  }
  restore_cleanup() {
    rm -rf "${restore_tmp:-}"
    unset CURRENT_POD_NAME CURRENT_SHARD_COMPONENT_SHORT_NAME \
      CURRENT_SHARD_POD_FQDN_LIST ALL_SHARDS_COMPONENT_SHORT_NAMES SERVICE_PORT VALKEY_DATA_DIR
  }
  write_offline_prepared_marker() {
    meta_digest=$(sha256sum "${restore_meta}" | awk '{print $1}')
    printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=vk-shard-abc-1\n' \
      '827eeab94f7421c651f6170d7d0e62cd4fad4594fb07faff4466acb01128ccd9' \
      "${meta_digest}" > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
  }
  Before "restore_env"
  After "restore_cleanup"

  It "accepts a disjoint in-domain slot-range list"
    When call validate_restore_slot_ranges "0-5460,10923-12000,12001"
    The status should be success
  End

  It "requires an explicit data directory instead of silently assuming /data"
    unset VALKEY_DATA_DIR
    When call cluster_restore_meta_path
    The status should be failure
    The stderr should include "phase=restore-env"
    The stderr should include "no data-path fallback"
  End

  It "rejects a dot-segment lifecycle data root before restore mutation"
    export VALKEY_DATA_DIR="${restore_tmp}/.."
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { echo SHOULD-NOT-PROBE; return 0; }

    When run post_provision
    The status should be failure
    The stderr should include "dot-segment alias"
    The stdout should not include "SHOULD-NOT-PROBE"
  End

  It "rejects overlapping slot ranges"
    When call validate_restore_slot_ranges "0-5460,5460-10922"
    The status should be failure
  End

  It "rejects an out-of-domain slot range"
    When call validate_restore_slot_ranges "0-16384"
    The status should be failure
  End

  It "returns only unassigned subranges already reserved for this restored shard"
    nodes='selfid self:6379@16379 myself,master - 0 0 1 connected 0-1
peerid peer:6379@16379 master - 0 0 2 connected 5-6'
    When call missing_restore_slot_ranges "${nodes}" "selfid" "0-4"
    The status should be success
    The stdout should equal "2-4"
  End

  It "fails closed when another master owns a desired restored slot"
    nodes='selfid self:6379@16379 myself,master - 0 0 1 connected 0-1
peerid peer:6379@16379 master - 0 0 2 connected 2-6'
    When call missing_restore_slot_ranges "${nodes}" "selfid" "0-4"
    The status should be failure
    The stderr should include "slot 2"
    The stderr should include "peerid"
  End

  It "fails closed when this master owns a slot outside its archived ranges"
    nodes='selfid self:6379@16379 myself,master - 0 0 1 connected 0-5'
    When call missing_restore_slot_ranges "${nodes}" "selfid" "0-4"
    The status should be failure
    The stderr should include "outside archived ranges"
  End

  It "refuses a source/target shard-count mismatch before cluster writes"
    sed -i.bak 's/source_shards=3/source_shards=4/' "${restore_meta}"
    meta_digest=$(sha256sum "${restore_meta}" | awk '{print $1}')
    printf 'phase=prepared\nmeta_sha256=%s\n' "${meta_digest}" \
      > "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
    build_cli() { _cli=(mock_ping); }
    mock_ping() { [ "$1" = PING ] && echo PONG; }
    build_cluster_cli() { _ccli=(mock_write_forbidden); }
    mock_write_forbidden() { echo WRITE-CALLED; return 99; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-shard-count"
    The stderr should include "retry_safe=no"
    The stdout should not include "WRITE-CALLED"
  End


  It "refuses missing restore-state before cluster writes"
    calls=$(mktemp)
    rm -f "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
    build_cli() { _cli=(mock_write_forbidden "${calls}"); }
    build_cluster_cli() { _ccli=(mock_write_forbidden "${calls}"); }
    mock_write_forbidden() { echo "$*" >> "$1"; return 99; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-state"
    The file "${calls}" should be empty file
  End

  It "uses only the deterministic coordinator to MEET fresh restored primaries"
    meet_log=$(mktemp)
    resolve_cluster_meet_address() {
      case "$1" in
        vk-shard-def-0.h) echo 10.0.0.2 ;;
        vk-shard-ghi-0.h) echo 10.0.0.3 ;;
      esac
    }
    build_cli() { _cli=(mock_restore_cli "$1" "${meet_log}"); }
    mock_restore_cli() {
      host="$1" log="$2"; shift 2
      case "$1" in
        PING) echo PONG ;;
        CLUSTER)
          if [ "$2" = MEET ]; then
            case "$3" in
              *[!0-9.]*) echo "ERR Invalid node address specified: $3:$4" ;;
              *) printf '%s\n' "$3" >> "${log}"; echo OK ;;
            esac
          fi ;;
      esac
    }
    cluster_nodes_of() { printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected\n'; }
    known_nodes_of() { echo 1; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-meet"
    The stderr should include "retry_safe=yes"
    The contents of file "${meet_log}" should equal "10.0.0.2
10.0.0.3"
  End

  It "resolves a restored peer FQDN to an IPv4 address for CLUSTER MEET"
    getent() {
      [ "$1" = ahostsv4 ] || return 1
      printf '10.0.0.2 STREAM %s\n' "$2"
      printf '10.0.0.2 DGRAM %s\n' "$2"
    }
    When call resolve_cluster_meet_address "vk-shard-def-0.h"
    The status should be success
    The stdout should equal "10.0.0.2"
  End

  It "rejects DNS output that is not a numeric IPv4 address"
    getent() { printf 'not-an-ip STREAM %s\n' "$2"; }
    When call resolve_cluster_meet_address "vk-shard-def-0.h"
    The status should be failure
    The stdout should be blank
  End

  It "does zero MEET writes when any fresh restored peer cannot resolve"
    meet_log=$(mktemp)
    resolve_cluster_meet_address() {
      [ "$1" = vk-shard-def-0.h ] && echo 10.0.0.2
    }
    build_cli() { _cli=(mock_restore_cli "$1" "${meet_log}"); }
    mock_restore_cli() {
      host="$1" log="$2"; shift 2
      case "$1" in
        PING) echo PONG ;;
        CLUSTER)
          [ "$2" = MEET ] && printf '%s\n' "$3" >> "${log}" && echo OK ;;
      esac
    }
    cluster_nodes_of() { printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected\n'; }
    known_nodes_of() { echo 1; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-dns"
    The stderr should include "retry_safe=yes"
    The file "${meet_log}" should be empty file
  End

  It "assigns only this archive's missing ranges after all primaries are mutually visible"
    slot_log=$(mktemp)
    build_cli() { _cli=(mock_slot_cli "$1" "${slot_log}"); }
    mock_slot_cli() {
      host="$1" log="$2"; shift 2
      case "$1" in
        PING) echo PONG ;;
        CLUSTER)
          [ "$2" = ADDSLOTSRANGE ] && printf '%s-%s\n' "$3" "$4" >> "${log}" && echo OK ;;
      esac
    }
    cluster_nodes_of() {
      printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected\n'
      printf 'id-def vk-shard-def-0.h:6379@16379 master - 0 0 2 connected\n'
      printf 'id-ghi vk-shard-ghi-0.h:6379@16379 master - 0 0 3 connected\n'
    }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-slots"
    The stderr should include "retry_safe=yes"
    The contents of file "${slot_log}" should equal "0-5460"
  End

  It "does zero writes when archived ranges conflict with another restored master"
    write_log=$(mktemp)
    build_cli() { _cli=(mock_conflict_cli "$1" "${write_log}"); }
    mock_conflict_cli() {
      host="$1" log="$2"; shift 2
      [ "$1" = PING ] && echo PONG
      [ "$1" = CLUSTER ] && printf 'WRITE %s\n' "$*" >> "${log}"
    }
    cluster_nodes_of() {
      printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected\n'
      printf 'id-def vk-shard-def-0.h:6379@16379 master - 0 0 2 connected 0-5460\n'
      printf 'id-ghi vk-shard-ghi-0.h:6379@16379 master - 0 0 3 connected 5461-16383\n'
    }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-slots"
    The stderr should include "retry_safe=no"
    The file "${write_log}" should be empty file
  End

  It "closes restored primary duties without waiting for later replica actions"
    attach_log=$(mktemp)
    build_cli() { _cli=(mock_full_cli); }
    mock_full_cli() { [ "$1" = PING ] && echo PONG; }
    cluster_nodes_of() {
      printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected 0-5460\n'
      printf 'id-def vk-shard-def-0.h:6379@16379 master - 0 0 2 connected 5461-10922\n'
      printf 'id-ghi vk-shard-ghi-0.h:6379@16379 master - 0 0 3 connected 10923-16383\n'
    }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    attach_all_replicas() { echo "FORBIDDEN-ATTACH:$1" >> "${attach_log}"; return 99; }
    cluster_formed_from_self() { echo FORBIDDEN-FULL-ROSTER; return 99; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be success
    The file "${attach_log}" should be empty file
    The file "${restore_meta}" should not be exist
    The contents of file "${VALKEY_DATA_DIR}/.kb-cluster-restore-state" should include "phase=formed"
    The stdout should include "restored primary duties complete"
    The stdout should not include "FORBIDDEN-FULL-ROSTER"
  End

  It "accepts only an empty slotless replica with the exact offline-prepared marker"
    write_offline_prepared_marker
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-new replica:6379@16379 myself,master - 0 0 0 connected\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    dbsize_of() { echo 0; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "offline-prepared"
  End

  It "refuses online cleanup when the restored target still contains data"
    calls=$(mktemp)
    write_offline_prepared_marker
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    dbsize_of() { echo 3; }
    build_cli() { _cli=(mock_no_write "${calls}"); }
    mock_no_write() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "refusing online cleanup"
    The file "${calls}" should be empty file
  End

  It "refuses an empty slotless target without the offline-prepared marker"
    calls=$(mktemp)
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-new replica:6379@16379 myself,master - 0 0 0 connected\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    dbsize_of() { echo 0; }
    build_cli() { _cli=(mock_no_write "${calls}"); }
    mock_no_write() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "lacks the exact offline-prepared marker"
    The file "${calls}" should be empty file
  End


  It "refuses an offline marker after cluster-meta changes"
    calls=$(mktemp)
    write_offline_prepared_marker
    printf '# changed after offline preparation\n' >> "${restore_meta}"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-new replica:6379@16379 myself,master - 0 0 0 connected\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    dbsize_of() { echo 0; }
    build_cli() { _cli=(mock_no_write "${calls}"); }
    mock_no_write() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "lacks the exact offline-prepared marker"
    The file "${calls}" should be empty file
  End

  It "never clears or re-prepares after the coordinator has already bound the replica"
    calls=$(mktemp)
    write_offline_prepared_marker
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h)
          printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n'
          printf 'id-rep vk-shard-abc-1.h:6379@16379 slave id-abc 0 0 1 connected\n' ;;
        *) echo SHOULD-NOT-READ-LOCAL-NODES; return 99 ;;
      esac
    }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    build_cli() { _cli=(mock_no_write "${calls}"); }
    mock_no_write() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "already bound to shard SHARD_ABC"
    The file "${calls}" should be empty file
  End


  It "rejects a symlinked prepared marker even when the replica is already bound"
    calls=$(mktemp)
    write_offline_prepared_marker
    outside_marker="${restore_tmp}/outside-prepared-marker"
    mv "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" "${outside_marker}"
    ln -s "${outside_marker}" "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h)
          printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n'
          printf 'id-rep vk-shard-abc-1.h:6379@16379 slave id-abc 0 0 1 connected\n' ;;
      esac
    }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    build_cli() { _cli=(mock_no_write "${calls}"); }
    mock_no_write() { echo "$*" >> "$1"; }

    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "lacks the exact offline-prepared marker"
    The file "${calls}" should be empty file
  End

  It "rejects a symlinked prepare marker beside a valid prepared marker before bound reentry"
    calls=$(mktemp)
    write_offline_prepared_marker
    outside_marker="${restore_tmp}/outside-prepare-marker"
    cp "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" "${outside_marker}"
    ln -s "${outside_marker}" "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h)
          printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n'
          printf 'id-rep vk-shard-abc-1.h:6379@16379 slave id-abc 0 0 1 connected\n' ;;
      esac
    }
    restored_primary_cluster_ready_for_replica_attach() { return 0; }
    build_cli() { _cli=(mock_no_write "${calls}"); }
    mock_no_write() { echo "$*" >> "$1"; }

    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "lacks the exact offline-prepared marker"
    The file "${calls}" should be empty file
  End

  It "does not run restore preparation during ordinary replica attach"
    offline_prepared_marker_matches() { echo UNSAFE-RESTORE-PREP; return 99; }
    build_cli() { _cli=(mock_no_member); }
    mock_no_member() { return 0; }
    build_cluster_cli() { _ccli=(mock_add_ok); }
    mock_add_ok() { echo OK; }
    When call ensure_replica_bound \
      "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "attached vk-shard-abc-1.h as replica"
    The stdout should not include "UNSAFE-RESTORE-PREP"
  End
  It "never lets the coordinator add an unbound restore replica"
    calls=$(mktemp)
    build_cli() { _cli=(mock_no_member); }
    mock_no_member() { return 0; }
    build_cluster_cli() { _ccli=(mock_forbidden_add "${calls}"); }
    mock_forbidden_add() { echo "$*" >> "$1"; }
    When call ensure_replica_bound \
      "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC" "restore"
    The status should be failure
    The stderr should include "phase=restore-replica-wait"
    The stderr should include "attach itself"
    The file "${calls}" should be empty file
  End

  It "lets the coordinator observe an already self-attached restore replica"
    build_cli() { _cli=(mock_bound_member); }
    mock_bound_member() {
      printf 'id-rep vk-shard-abc-1.h:6379@16379 slave id-abc 0 0 1 connected\n'
    }
    When call ensure_replica_bound \
      "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC" "restore"
    The status should be success
  End

  It "defers primary completion until every restored primary view is fully converged"
    attach_log=$(mktemp)
    build_cli() { _cli=(mock_full_cli); }
    mock_full_cli() { [ "$1" = PING ] && echo PONG; }
    cluster_nodes_of() {
      printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected 0-5460\n'
      printf 'id-def vk-shard-def-0.h:6379@16379 master - 0 0 2 connected 5461-10922\n'
      printf 'id-ghi vk-shard-ghi-0.h:6379@16379 master - 0 0 3 connected 10923-16383\n'
    }
    cluster_state_of() { [ "$1" = vk-shard-def-0.h ] && echo fail || echo ok; }
    assigned_slots_of() { echo 16384; }
    attach_all_replicas() { echo ATTACH >> "${attach_log}"; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stderr should include "phase=restore-primary-converge"
    The stderr should include "one exact id set"
    The file "${attach_log}" should be empty file
  End

  It "keeps the primary-view gate valid after an earlier replica has attached"
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    cluster_nodes_of() {
      printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected 0-5460\n'
      printf 'id-def vk-shard-def-0.h:6379@16379 master - 0 0 2 connected 5461-10922\n'
      printf 'id-ghi vk-shard-ghi-0.h:6379@16379 master - 0 0 3 connected 10923-16383\n'
      printf 'id-rep vk-shard-abc-1.h:6379@16379 slave id-abc 0 0 4 connected\n'
    }
    When call restored_primary_cluster_ready_for_replica_attach
    The status should be success
  End

  It "fails the primary-view gate when an attached replica is not visible everywhere"
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    cluster_nodes_of() {
      printf 'id-abc vk-shard-abc-0.h:6379@16379 master - 0 0 1 connected 0-5460\n'
      printf 'id-def vk-shard-def-0.h:6379@16379 master - 0 0 2 connected 5461-10922\n'
      printf 'id-ghi vk-shard-ghi-0.h:6379@16379 master - 0 0 3 connected 10923-16383\n'
      [ "$1" = "vk-shard-abc-0.h" ] && \
        printf 'id-rep vk-shard-abc-1.h:6379@16379 slave id-abc 0 0 4 connected\n'
    }
    When call restored_primary_cluster_ready_for_replica_attach
    The status should be failure
  End

  It "routes a local restore marker to the slot-aware path and never ordinary create"
    export VALKEY_DATA_DIR="${restore_tmp}"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 1; }
    restore_cluster_from_meta() { echo "RESTORE-PATH:$1"; return 0; }
    form_cluster() { echo ORDINARY-CREATE-PATH; return 99; }
    When run post_provision
    The status should be success
    The stdout should include "RESTORE-PATH:${restore_meta}"
    The stdout should not include "ORDINARY-CREATE-PATH"
  End

  It "lets a restored non-first pod attach and close only its local formed state"
    export CURRENT_POD_NAME="vk-shard-abc-1"
    build_cli() { _cli=(mock_ping); }
    mock_ping() { [ "$1" = PING ] && echo PONG; }
    node_id_of() { [ "$1" = vk-shard-abc-0.h ] && echo id-abc; }
    prepare_local_restored_replica_for_attach() {
      echo "LOCAL-PREP:$2:$3:$4:$5"
      return 0
    }
    ensure_replica_bound() {
      echo "LOCAL-ATTACH:$1:$2:$3:$4:${5:-ordinary}"
      return 0
    }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be success
    The stdout should include "LOCAL-PREP:vk-shard-abc-0.h:vk-shard-abc-1.h:id-abc:shard-abc"
    The stdout should include "LOCAL-ATTACH:vk-shard-abc-0.h:vk-shard-abc-1.h:id-abc:shard-abc:ordinary"
    The stdout should include "LOCAL-ATTACH:vk-shard-abc-0.h:vk-shard-abc-1.h:id-abc:shard-abc:restore"
    The stdout should include "restored replica duties complete"
    The contents of file "${VALKEY_DATA_DIR}/.kb-cluster-restore-state" should include "phase=formed"
  End

  It "removes the local restore marker only after positive cluster formation"
    export VALKEY_DATA_DIR="${restore_tmp}"
    : > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare"
    : > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 0; }
    restore_cluster_from_meta() { echo RESTORE-PATH; return 99; }
    When run post_provision
    The status should be success
    The file "${restore_meta}" should not be exist
    The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare" should not be exist
    The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" should not be exist
    The contents of file "${VALKEY_DATA_DIR}/.kb-cluster-restore-state" should include "phase=formed"
    The stdout should include "committed local cluster restore formed state"
    The stdout should not include "RESTORE-PATH"
  End


  It "accepts a formed local tombstone without global convergence or new writes"
    export VALKEY_DATA_DIR="${restore_tmp}"
    meta_digest=$(sha256sum "${restore_meta}" | awk '{print $1}')
    printf 'phase=formed\nmeta_sha256=%s\n' "${meta_digest}" \
      > "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
    rm -f "${restore_meta}"
    : > "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 1; }
    mark_local_cluster_restore_formed() { echo FORBIDDEN-MUTATION; return 99; }
    When run post_provision
    The status should be success
    The file "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" should be exist
    The stdout should include "local restore duties already complete"
    The stdout should not include "FORBIDDEN-MUTATION"
  End

  It "rejects a malformed local formed tombstone without cluster-meta"
    export VALKEY_DATA_DIR="${restore_tmp}"
    printf 'phase=formed\nmeta_sha256=short\n' \
      > "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
    rm -f "${restore_meta}"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 1; }
    form_cluster() { echo ORDINARY-FORMATION; return 99; }

    When run post_provision
    The status should be failure
    The stderr should include "invalid local formed-state metadata identity"
    The stdout should not include "ORDINARY-FORMATION"
  End

  It "rejects a symlinked cluster-meta on the already-formed fast path"
    export VALKEY_DATA_DIR="${restore_tmp}"
    outside_meta="${restore_tmp}/outside-cluster-meta"
    mv "${restore_meta}" "${outside_meta}"
    ln -s "${outside_meta}" "${restore_meta}"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 0; }

    When run post_provision
    The status should be failure
    The stderr should include "is a symlink"
    The file "${outside_meta}" should be exist
  End

  It "rejects a dangling restore-state symlink instead of treating it as absent"
    export VALKEY_DATA_DIR="${restore_tmp}"
    rm -f "${restore_meta}" "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
    ln -s "${restore_tmp}/missing-state" "${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 1; }
    form_cluster() { echo ORDINARY-FORMATION; return 99; }

    When run post_provision
    The status should be failure
    The stderr should include "is a symlink"
    The stdout should not include "ORDINARY-FORMATION"
  End
End
