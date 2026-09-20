#!/bin/bash
# valkey-sentinel-member-leave.sh — memberLeave action of the Sentinel component.
#
# KubeBlocks calls this action when a Sentinel pod is leaving the component
# (scale-in of the Sentinel set, e.g. 5 → 3 Sentinels, or pod removal).  The
# data component's own memberLeave was removed on purpose — Sentinel self-heals
# the data topology — but a *Sentinel* leaving needs explicit bookkeeping: the
# other Sentinels keep the leaving one in their known-sentinel lists until the
# pub/sub HELLO gossip times it out, and during that window a client or replica
# may still be handed the leaving Sentinel's answer.
#
# Three steps (same flow as the redis addon's redis-sentinel-member-leave.sh):
#   1. On the LEAVING Sentinel: wait until every monitored master is reachable,
#      then `SENTINEL REMOVE <name>` each one — the dying node stops monitoring
#      and stops announcing itself via HELLO immediately, instead of lingering
#      as a voter/campaigner until the pod is actually deleted.
#   2. On every REMAINING Sentinel: `SENTINEL RESET "*"` — forced re-discovery
#      drops the leaving node from the known-sentinel lists right away.
#   3. Verify agreement: all remaining Sentinels must report the same
#      num-other-sentinels per master.  A mismatch means one node did not
#      finish its re-discovery — fail the action so KubeBlocks retries.
#
# KubeBlocks injects for memberLeave:
#   KB_LEAVE_MEMBER_POD_NAME   — name of the leaving Sentinel pod
#   KB_LEAVE_MEMBER_POD_FQDN   — FQDN of the leaving Sentinel pod
# Component vars used:
#   SENTINEL_POD_FQDN_LIST     — all Sentinel pod FQDNs (comma separated)
#   SENTINEL_PASSWORD          — Sentinel auth password (may be empty)
#   SENTINEL_SERVICE_PORT      — Sentinel port (default 26379)
#   VALKEY_CLI_TLS_ARGS        — TLS flags for valkey-cli (may be empty)
#
# Fail-closed: step 1 is best-effort (the leaving pod may already be dying),
# but steps 2 and 3 exit non-zero on failure so KubeBlocks does not silently
# accept a half-left Sentinel.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

# Ports are constant for the pod, so they are resolved once at load time — the
# same style as the other valkey scripts.
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"

declare -g sentinel_leave_member_name
declare -g sentinel_leave_member_fqdn
declare -a sentinel_pod_list=()
declare -A other_sentinel_counts=()

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

build_sentinel_cli() {
  local host="${1}"
  _sentinel_cli_cmd=(valkey-cli --no-auth-warning -h "${host}" -p "${sentinel_port}")
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    _sentinel_cli_cmd+=(-a "${SENTINEL_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    _sentinel_cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# pod_name_of_fqdn <fqdn> — first DNS label of a pod FQDN equals the pod name
# (e.g. "valkey-valkey-sentinel-0.<headless>.<ns>.svc" → "valkey-valkey-sentinel-0").
pod_name_of_fqdn() {
  echo "${1%%.*}"
}

# sentinel_member_get — validate the injected identity vars and split the
# Sentinel peer list.  Exits 1 when a required var is missing: without them the
# script cannot tell which node is leaving, and guessing is worse than failing.
sentinel_member_get() {
  if is_empty "${KB_LEAVE_MEMBER_POD_FQDN}"; then
    echo "ERROR: required environment variable KB_LEAVE_MEMBER_POD_FQDN is not set." >&2
    exit 1
  fi
  if is_empty "${KB_LEAVE_MEMBER_POD_NAME}"; then
    echo "ERROR: required environment variable KB_LEAVE_MEMBER_POD_NAME is not set." >&2
    exit 1
  fi
  if is_empty "${SENTINEL_POD_FQDN_LIST}"; then
    echo "ERROR: required environment variable SENTINEL_POD_FQDN_LIST is not set." >&2
    exit 1
  fi
  sentinel_leave_member_name="${KB_LEAVE_MEMBER_POD_NAME}"
  sentinel_leave_member_fqdn="${KB_LEAVE_MEMBER_POD_FQDN}"
  # shellcheck disable=SC2207
  sentinel_pod_list=($(split "${SENTINEL_POD_FQDN_LIST}" ","))
}

# get_masters <host> — capture `SENTINEL masters` from one Sentinel into
# temp_output (empty on connection failure).
get_masters() {
  local host="${1}"
  build_sentinel_cli "${host}"
  temp_output=$("${_sentinel_cli_cmd[@]}" sentinel masters 2>/dev/null) || true
}

# masters_reachable — 0 when temp_output is non-empty and no master carries a
# disconnected flag (a disconnected master would make REMOVE decisions unsafe).
masters_reachable() {
  local line flags=""
  if is_empty "${temp_output}"; then
    return 1
  fi
  local marker=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ -n "${marker}" ]; then
      case "${marker}" in
        flags) flags="${line}" ;;
      esac
      marker=""
      continue
    fi
    case "${line}" in
      flags) marker="flags" ;;
    esac
  done <<< "${temp_output}"
  case ",${flags}," in
    *,disconnected,*) return 1 ;;
  esac
  return 0
}

# remove_monitor — on the leaving Sentinel: wait until all masters are
# reachable, then `SENTINEL REMOVE <name>` each monitored master.  Best-effort:
# when the leaving Sentinel is already unreachable the remaining steps still
# run (RESET makes the peers forget it regardless).
remove_monitor() {
  local retries success output master_name
  retries=0
  success=false
  output=""
  while [ "${retries}" -lt 3 ]; do
    get_masters "${sentinel_leave_member_fqdn}"
    if [ "${?}" -eq 0 ]; then
      if is_empty "${temp_output}"; then
        echo "no master nodes found."
        success=true
        break
      fi
      if masters_reachable; then
        echo "all masters are reachable."
        success=true
        output="${temp_output}"
        break
      fi
      retries=$((retries + 1))
      echo "one or more masters are disconnected. ${retries}/3 failed. retrying..."
    else
      retries=$((retries + 1))
      echo "timeout waiting for ${sentinel_leave_member_fqdn} to become available ${retries}/3 failed. retrying..."
    fi
    sleep_when_ut_mode_false 1
  done
  if [ "${success}" = "true" ]; then
    echo "connected to the sentinel successfully after ${retries} retries"
  else
    echo "sentinel connect failed after 3 retries."
  fi
  if ! is_empty "${output}"; then
    master_name=""
    local marker=""
    local line
    while IFS= read -r line; do
      line="${line%$'\r'}"
      if [ -n "${marker}" ]; then
        case "${marker}" in
          name) master_name="${line}" ;;
        esac
        marker=""
      fi
      case "${line}" in
        name) marker="name" ;;
      esac
      if ! is_empty "${master_name}"; then
        echo "master name: ${master_name}"
        build_sentinel_cli "${sentinel_leave_member_fqdn}"
        "${_sentinel_cli_cmd[@]}" SENTINEL REMOVE "${master_name}" || true
        echo "sentinel no longer monitors ${master_name}"
        master_name=""
      fi
    done <<< "${output}"
  else
    echo "unable to connect to valkey sentinel, or no master nodes found."
  fi
}

# reset_remaining_sentinels — `SENTINEL RESET "*"` on every non-leaving
# Sentinel (with retries): RESET forces the peer to drop its known-sentinel
# and known-replica lists and re-discover, which forgets the leaving node
# immediately instead of waiting for the HELLO gossip to time it out.
reset_remaining_sentinels() {
  local sentinel_pod pod_name retries success reset_out
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    pod_name="$(pod_name_of_fqdn "${sentinel_pod}")"
    [ "${pod_name}" != "${sentinel_leave_member_name}" ] || continue
    retries=0
    success=false
    while [ "${retries}" -lt 3 ]; do
      build_sentinel_cli "${sentinel_pod}"
      # valkey-cli exits non-zero on connection failure but still exits 0 for
      # some protocol errors, and a failed connection prints a non-empty error
      # text — so accept only a clean "OK" answer, never "non-empty output".
      reset_out=$("${_sentinel_cli_cmd[@]}" SENTINEL RESET "*" 2>&1) || true
      reset_out="${reset_out//$'\r'/}"
      if [ "${reset_out}" = "OK" ]; then
        echo "sentinel is resetting at ${sentinel_pod} on port ${sentinel_port}."
        success=true
        break
      fi
      retries=$((retries + 1))
      echo "retry ${retries}/3 for sentinel reset at ${sentinel_pod} failed. retrying..."
      sleep_when_ut_mode_false 1
    done
    if [ "${success}" = "true" ]; then
      echo "connected to the sentinel successfully after ${retries} retries"
      # Give the re-discovery a moment so the agreement check below sees the
      # post-RESET state instead of the pre-RESET one.
      sleep_when_ut_mode_false 3
    else
      echo "ERROR: sentinel connect failed after 3 retries at ${sentinel_pod}." >&2
      exit 1
    fi
  done
  echo "all remaining sentinels have been reset."
}

# check_all_sentinel_agreement — every remaining Sentinel must report the same
# num-other-sentinels per master.  After a clean RESET of N-1 remaining nodes
# (one leaving) each should see the same peer count; a mismatch means one node
# did not finish its re-discovery and may still route through the leaver.
check_all_sentinel_agreement() {
  local sentinel_pod pod_name retries success line marker
  local master_name num_other
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    pod_name="$(pod_name_of_fqdn "${sentinel_pod}")"
    [ "${pod_name}" != "${sentinel_leave_member_name}" ] || continue
    echo "sentinel_pod ${sentinel_pod}"
    retries=0
    success=false
    while [ "${retries}" -lt 3 ]; do
      get_masters "${sentinel_pod}"
      if masters_reachable; then
        echo "all masters are reachable."
        success=true
        break
      fi
      retries=$((retries + 1))
      echo "timeout waiting for ${sentinel_pod} to become available ${retries}/3 failed. retrying..."
      sleep_when_ut_mode_false 1
    done
    if [ "${success}" != "true" ]; then
      echo "sentinel connect failed after 3 retries, it is either faulty or has already been shut down."
      continue
    fi
    master_name=""
    num_other=""
    marker=""
    while IFS= read -r line; do
      line="${line%$'\r'}"
      if [ -n "${marker}" ]; then
        case "${marker}" in
          name)               master_name="${line}" ;;
          num-other-sentinels) num_other="${line}" ;;
        esac
        marker=""
      else
        case "${line}" in
          name|num-other-sentinels) marker="${line}" ;;
        esac
      fi
      if ! is_empty "${master_name}" && ! is_empty "${num_other}"; then
        echo "master name: ${master_name}, num-other-sentinels: ${num_other}"
        if [ -z "${other_sentinel_counts[${master_name}]:-}" ]; then
          other_sentinel_counts["${master_name}"]="${num_other}"
        elif [ "${other_sentinel_counts[${master_name}]}" -ne "${num_other}" ]; then
          echo "ERROR: sentinels disagree about num-other-sentinels of ${master_name} (${other_sentinel_counts[${master_name}]} vs ${num_other}); reset failed." >&2
          exit 1
        fi
        master_name=""
        num_other=""
      fi
    done <<< "${temp_output}"
  done
  echo "all the sentinels agree about the number of sentinels currently active"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library
sentinel_member_get
remove_monitor
reset_remaining_sentinels
check_all_sentinel_agreement
