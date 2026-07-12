# shellcheck shell=bash
# shellcheck disable=SC2034

Describe "Valkey cluster restore slot contract"
  Include ../scripts/valkey-cluster-manage.sh

  restore_env() {
    restore_tmp=$(mktemp -d "${TMPDIR:-/tmp}/valkey-cluster-restore.XXXXXX")
    restore_meta="${restore_tmp}/cluster-meta"
    cat > "${restore_meta}" <<'META'
source_shards=3
shard_master_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
shard_slot_ranges=0-5460
rdb_sha256=827eeab94f7421c651f6170d7d0e62cd4fad4594fb07faff4466acb01128ccd9
META
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

  It "attaches replicas and removes metadata only after exact full-slot proof"
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
    attach_all_replicas() { echo "ATTACH:$1" >> "${attach_log}"; }
    cluster_formed_from_self() { return 0; }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be success
    The contents of file "${attach_log}" should equal "ATTACH:restore"
    The file "${restore_meta}" should not be exist
    The stdout should include "restored cluster formed with archived slot ownership"
  End

  It "locally clears and hard-resets only an archive-verified restored duplicate"
    calls=$(mktemp)
    reset_done=$(mktemp)
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h)
          printf 'id-abc vk-shard-abc-0.h:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h)
          if [ -s "${reset_done}" ]; then
            printf 'id-new vk-shard-abc-1.h:6379@16379 myself,master - 0 0 0 connected\n'
          else
            printf 'id-old vk-shard-abc-1.h:6379@16379 myself,master - 0 0 0 connected 1 4-5\n'
          fi ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { [ "$1" = vk-shard-abc-1.h ] && [ -s "${calls}" ] && echo 0 || echo 3; }
    build_cli() { _cli=(mock_replica_reset "$1" "${calls}" "${reset_done}"); }
    mock_replica_reset() {
      host="$1" log="$2" reset="$3"; shift 3
      case "$*" in
        FLUSHALL) echo "FLUSHALL:${host}" >> "${log}"; echo OK ;;
        "CLUSTER RESET HARD") echo "RESET:${host}" >> "${log}"; echo yes > "${reset}"; echo OK ;;
      esac
    }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "prepared local restored duplicate"
    The contents of file "${calls}" should equal "FLUSHALL:vk-shard-abc-1.h
RESET:vk-shard-abc-1.h"
  End

  It "does zero local reset writes until every restored primary view converges"
    calls=$(mktemp)
    restored_primary_cluster_ready_for_replica_reset() { return 1; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "phase=restore-replica-primary"
    The stderr should include "all restored primary views"
    The file "${calls}" should be empty file
  End

  It "refuses to clear a restored replica when dump.rdb differs from backup metadata"
    calls=$(mktemp)
    printf 'different snapshot\n' > "${VALKEY_DATA_DIR}/dump.rdb"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 3; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "phase=restore-replica-data"
    The stderr should include "retry_safe=no"
    The file "${calls}" should be empty file
  End

  It "refuses to clear a restored replica whose singleton slots are foreign to its shard master"
    calls=$(mktemp)
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 6000\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 3; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "phase=restore-replica-slots"
    The stderr should include "retry_safe=no"
    The file "${calls}" should be empty file
  End

  It "refuses to clear a restored replica with post-restore AOF writes"
    calls=$(mktemp)
    printf 'SET unexpected value\n' > "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.1.incr.aof"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 3; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "phase=restore-replica-data"
    The stderr should include "multipart AOF"
    The file "${calls}" should be empty file
  End

  It "refuses to clear a restored replica with unexpected multipart AOF files"
    calls=$(mktemp)
    : > "${VALKEY_DATA_DIR}/appendonlydir/appendonly.aof.2.incr.aof"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 3; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "phase=restore-replica-data"
    The stderr should include "multipart AOF"
    The file "${calls}" should be empty file
  End

  It "resumes at hard reset when a prior restore invocation already emptied the duplicate"
    calls=$(mktemp)
    reset_done=$(mktemp)
    cat > "${VALKEY_DATA_DIR}/.kb-restored-replica-reset-authorized" <<'MARKER'
rdb_sha256=827eeab94f7421c651f6170d7d0e62cd4fad4594fb07faff4466acb01128ccd9
master_id=id-abc
shard=SHARD_ABC
pod=vk-shard-abc-1
MARKER
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h)
          if [ -s "${reset_done}" ]; then
            printf 'id-new replica:6379@16379 myself,master - 0 0 0 connected\n'
          else
            printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n'
          fi ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 0; }
    build_cli() { _cli=(mock_reset_only "$1" "${calls}" "${reset_done}"); }
    mock_reset_only() {
      host="$1" log="$2" reset="$3"; shift 3
      case "$*" in
        FLUSHALL) echo "UNEXPECTED-FLUSH:${host}" >> "${log}" ;;
        "CLUSTER RESET HARD") echo "RESET:${host}" >> "${log}"; echo yes > "${reset}"; echo OK ;;
      esac
    }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "prepared local restored duplicate"
    The contents of file "${calls}" should equal "RESET:vk-shard-abc-1.h"
    The file "${VALKEY_DATA_DIR}/.kb-restored-replica-reset-authorized" should not be exist
  End

  It "does zero reset writes for an empty slot-owning target without authorization"
    calls=$(mktemp)
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 0; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "phase=restore-replica-data"
    The stderr should include "without reset authorization"
    The file "${calls}" should be empty file
  End

  It "does zero reset writes when the authorization belongs to another target"
    calls=$(mktemp)
    printf 'rdb_sha256=%s\nmaster_id=wrong\nshard=SHARD_ABC\npod=vk-shard-abc-1\n' \
      '827eeab94f7421c651f6170d7d0e62cd4fad4594fb07faff4466acb01128ccd9' \
      > "${VALKEY_DATA_DIR}/.kb-restored-replica-reset-authorized"
    cluster_nodes_of() {
      case "$1" in
        vk-shard-abc-0.h) printf 'id-abc primary:6379@16379 myself,master - 0 0 1 connected 0-5460\n' ;;
        vk-shard-abc-1.h) printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n' ;;
      esac
    }
    known_nodes_of() { echo 1; }
    cluster_state_of() { echo ok; }
    assigned_slots_of() { echo 16384; }
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    dbsize_of() { echo 0; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be failure
    The stderr should include "authorization marker does not match"
    The file "${calls}" should be empty file
  End

  It "never clears again after the coordinator has already bound the replica"
    calls=$(mktemp)
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
    restored_primary_cluster_ready_for_replica_reset() { return 0; }
    build_cli() { _cli=(mock_no_reset "${calls}"); }
    mock_no_reset() { echo "$*" >> "$1"; }
    When call prepare_local_restored_replica_for_attach \
      "${restore_meta}" "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "already bound to shard SHARD_ABC"
    The file "${calls}" should be empty file
  End

  It "does not run restore reset preparation during ordinary replica attach"
    restored_replica_ready_for_attach() { echo UNSAFE-RESTORE-RESET; return 99; }
    build_cli() { _cli=(mock_no_member); }
    mock_no_member() { return 0; }
    build_cluster_cli() { _ccli=(mock_add_ok); }
    mock_add_ok() { echo OK; }
    When call ensure_replica_bound \
      "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC"
    The status should be success
    The stdout should include "attached vk-shard-abc-1.h as replica"
    The stdout should not include "UNSAFE-RESTORE-RESET"
  End

  It "does not issue add-node in restore mode until the replica self-prepares"
    calls=$(mktemp)
    build_cli() { _cli=(mock_no_member); }
    mock_no_member() { return 0; }
    known_nodes_of() { echo 1; }
    cluster_nodes_of() { printf 'id-old replica:6379@16379 myself,master - 0 0 0 connected 1-2\n'; }
    dbsize_of() { echo 3; }
    build_cluster_cli() { _ccli=(mock_forbidden_add "${calls}"); }
    mock_forbidden_add() { echo "$*" >> "$1"; }
    When call ensure_replica_bound \
      "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC" "restore"
    The status should be failure
    The stderr should include "phase=restore-replica-wait"
    The file "${calls}" should be empty file
  End

  It "issues restore add-node only after the replica is one empty slotless node"
    build_cli() { _cli=(mock_no_member); }
    mock_no_member() { return 0; }
    known_nodes_of() { echo 1; }
    cluster_nodes_of() { printf 'id-new replica:6379@16379 myself,master - 0 0 0 connected\n'; }
    dbsize_of() { echo 0; }
    build_cluster_cli() { _ccli=(mock_add_ok); }
    mock_add_ok() { echo OK; }
    When call ensure_replica_bound \
      "vk-shard-abc-0.h" "vk-shard-abc-1.h" "id-abc" "SHARD_ABC" "restore"
    The status should be success
    The stdout should include "attached vk-shard-abc-1.h as replica"
  End

  It "defers before replica reset until every restored primary view is fully converged"
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
    The stderr should include "phase=restore-attach"
    The stderr should include "before replica reset"
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
    When call restored_primary_cluster_ready_for_replica_reset
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
    When call restored_primary_cluster_ready_for_replica_reset
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

  It "routes a restored non-first pod through local replica preparation"
    export CURRENT_POD_NAME="vk-shard-abc-1"
    build_cli() { _cli=(mock_ping); }
    mock_ping() { [ "$1" = PING ] && echo PONG; }
    node_id_of() { [ "$1" = vk-shard-abc-0.h ] && echo id-abc; }
    prepare_local_restored_replica_for_attach() {
      echo "LOCAL-PREP:$2:$3:$4:$5"
      return 0
    }
    When call restore_cluster_from_meta "${restore_meta}"
    The status should be failure
    The stdout should include "LOCAL-PREP:vk-shard-abc-0.h:vk-shard-abc-1.h:id-abc:shard-abc"
  End

  It "removes the local restore marker only after positive cluster formation"
    export VALKEY_DATA_DIR="${restore_tmp}"
    validate_manage_env() { return 0; }
    cluster_formed_from_self() { return 0; }
    restore_cluster_from_meta() { echo RESTORE-PATH; return 99; }
    When run post_provision
    The status should be success
    The file "${restore_meta}" should not be exist
    The stdout should include "removed local cluster restore metadata after positive formation proof"
    The stdout should not include "RESTORE-PATH"
  End
End
