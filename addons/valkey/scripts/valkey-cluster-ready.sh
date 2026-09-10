#!/bin/sh

port="${SERVICE_PORT:-6379}"
data_dir="${VALKEY_DATA_DIR:-/data}"
marker="${data_dir}/.kb-valkey-cluster-formed"

run_cli() {
  # VALKEY_CLI_TLS_ARGS intentionally expands into separate CLI arguments.
  # shellcheck disable=SC2086
  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}" \
      -a "${VALKEY_DEFAULT_PASSWORD}" ${VALKEY_CLI_TLS_ARGS:-} "$@"
  else
    valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}" \
      ${VALKEY_CLI_TLS_ARGS:-} "$@"
  fi
}

# Readiness is the public service gate, not merely process liveness.
response=$(run_cli PING 2>/dev/null) || exit 1
[ "${response}" = "PONG" ] || exit 1

cluster_info_value() {
  printf '%s\n' "${info}" | awk -F: -v key="$1" '
    $1 == key { gsub(/\r/, "", $2); value=$2; count++ }
    END { if (count != 1 || value == "") exit 1; print value }
  '
}

cluster_is_healthy() {
  info=$(run_cli CLUSTER INFO 2>/dev/null) || return 1
  [ "$(cluster_info_value cluster_state)" = "ok" ] &&
    [ "$(cluster_info_value cluster_slots_assigned)" = "16384" ] &&
    [ "$(cluster_info_value cluster_slots_ok)" = "16384" ] &&
    [ "$(cluster_info_value cluster_slots_pfail)" = "0" ] &&
    [ "$(cluster_info_value cluster_slots_fail)" = "0" ]
}

cluster_is_healthy || exit 1

marker_is_formed() {
  [ ! -L "${marker}" ] &&
    [ -f "${marker}" ] &&
    [ "$(cat "${marker}" 2>/dev/null)" = "formed" ]
}

# postProvision commits the marker during initial formation. Replica scale-out
# instead converges through memberJoin, which cannot write the joining Pod's
# PVC. Recover the local marker only from a strict engine-side membership
# proof: the current node is connected and is either a slot-owning master or a
# replica bound to a connected slot-owning master in its own cluster view.
local_membership_is_formed() {
  nodes=$(run_cli CLUSTER NODES 2>/dev/null) || return 1
  printf '%s\n' "${nodes}" | awk '
    function has_flag(flags, wanted, count, values, i) {
      count = split(flags, values, ",")
      for (i = 1; i <= count; i++) {
        if (values[i] == wanted) return 1
      }
      return 0
    }
    function has_bad_flag(flags) {
      return has_flag(flags, "fail") ||
        has_flag(flags, "handshake") ||
        has_flag(flags, "noaddr")
    }
    function owns_slots(first, i) {
      for (i = first; i <= NF; i++) {
        if ($i ~ /^[0-9]+(-[0-9]+)?$/) return 1
      }
      return 0
    }
    NF >= 8 {
      id_count[$1]++
      flags[$1] = $3
      link_state[$1] = $8
      slot_owner[$1] = owns_slots(9)
      if (has_flag($3, "myself")) {
        self_count++
        self_flags = $3
        self_master = $4
        self_link_state = $8
        self_slot_owner = owns_slots(9)
      }
    }
    END {
      if (self_count != 1 || self_link_state != "connected" ||
          has_bad_flag(self_flags)) exit 1

      if (has_flag(self_flags, "slave")) {
        if (self_master == "-" || id_count[self_master] != 1 ||
            !has_flag(flags[self_master], "master") ||
            has_bad_flag(flags[self_master]) ||
            link_state[self_master] != "connected" ||
            !slot_owner[self_master]) exit 1
        exit 0
      }

      if (has_flag(self_flags, "master") && self_slot_owner) exit 0
      exit 1
    }
  '
}

commit_formed_marker() {
  temporary=$(mktemp "${marker}.tmp.XXXXXX") || return 1
  if ! printf 'formed\n' > "${temporary}"; then
    rm -f "${temporary}"
    return 1
  fi

  # A hard-link commit is atomic and no-clobber. If another probe wins the
  # race, accept only its exact safe marker; never replace an unexpected path.
  if ln "${temporary}" "${marker}" 2>/dev/null; then
    rm -f "${temporary}"
    return 0
  fi
  rm -f "${temporary}"
  marker_is_formed
}

if [ -L "${marker}" ] || [ -e "${marker}" ]; then
  marker_is_formed || exit 1
else
  local_membership_is_formed || exit 1
  # Close the observation window before persisting readiness: membership
  # inspection may race with a cluster-state transition.
  cluster_is_healthy || exit 1
  umask 077
  commit_formed_marker || exit 1
fi
