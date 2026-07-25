#!/usr/bin/env bash

restore_state_required_env=(
  KB_DP_RESTORE_NAMESPACE
  KB_DP_RESTORE_NAME
  KB_DP_RESTORE_UID
  KB_DP_RESTORE_ACTION
  KB_DP_RESTORE_ACTION_ORDINAL
  KB_DP_AUTHORIZATION_GENERATION
  KB_DP_AUTHORIZATION_NONCE
  KB_DP_RESTORE_IDENTITY_SHA
  KB_DP_JOB_NAME
  KB_DP_JOB_UID
  KB_DP_POD_NAME
  KB_DP_POD_UID
)

restore_state_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
    return
  fi
  shasum -a 256 | awk '{print $1}'
}

restore_state_validate_identity() {
  local name
  for name in "${restore_state_required_env[@]}"; do
    if [ -z "${!name:-}" ]; then
      echo "ERROR: missing restore identity env ${name}" >&2
      return 1
    fi
  done

  local actual
  actual=$(
    printf '%s\0%s\0%s\0%s\0%s' \
      "$KB_DP_RESTORE_UID" \
      "$KB_DP_RESTORE_NAMESPACE" \
      "$KB_DP_RESTORE_NAME" \
      "$KB_DP_RESTORE_ACTION" \
      "$KB_DP_RESTORE_ACTION_ORDINAL" |
      restore_state_sha256
  )
  if [ "$actual" != "$KB_DP_RESTORE_IDENTITY_SHA" ]; then
    echo "ERROR: restore identity SHA mismatch" >&2
    return 1
  fi
}

restore_state_execution_dir() {
  printf '%s/executions/%s/%s' \
    "$1" "$KB_DP_JOB_UID" "$KB_DP_POD_UID"
}

restore_state_write_lock_timeout_receipt() {
  local action_root="$1"
  local lock_name="$2"
  local execution_dir
  execution_dir=$(restore_state_execution_dir "$action_root")
  mkdir -p "$execution_dir" || return 1
  (
    set -o noclobber
    printf 'kind=LOCK_ACQUIRE_TIMEOUT\nlock=%s\njobUID=%s\npodUID=%s\n' \
      "$lock_name" "$KB_DP_JOB_UID" "$KB_DP_POD_UID" \
      >"$execution_dir/terminal"
  ) 2>/dev/null || true
}

restore_state_acquire_lock() {
  local lock_path="$1"
  local action_root="$2"
  local lock_name="$3"
  local held_path="${lock_path}.held"
  local attempts=0

  while [ "$attempts" -lt 20 ]; do
    if mkdir "$held_path" 2>/dev/null; then
      printf 'jobUID=%s\npodUID=%s\n' \
        "$KB_DP_JOB_UID" "$KB_DP_POD_UID" \
        >"${held_path}/owner"
      RESTORE_STATE_HELD_LOCK="$held_path"
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.25
  done
  restore_state_write_lock_timeout_receipt "$action_root" "$lock_name"
  return 2
}

restore_state_release_lock() {
  if [ -n "${RESTORE_STATE_HELD_LOCK:-}" ]; then
    rm -f "${RESTORE_STATE_HELD_LOCK}/owner"
    rmdir "$RESTORE_STATE_HELD_LOCK" 2>/dev/null || true
    RESTORE_STATE_HELD_LOCK=""
  fi
}

# Returns 0 for the only execution allowed to dispatch ALTER SYSTEM RESTORE.
# Returns 10 for observer-only retries and 11 for a bounded lock timeout.
restore_state_claim_dispatch() {
  local tenant_name="$1"
  local work_root="${KB_DP_RESTORE_STATE_ROOT:-/home/admin/workdir/restore-intents}"
  local action_root="${work_root}/${KB_DP_RESTORE_IDENTITY_SHA}"
  local tenant_sha
  tenant_sha=$(printf '%s' "$tenant_name" | restore_state_sha256) || return 1
  local tenant_root="${action_root}/tenants/${tenant_sha}"

  restore_state_validate_identity || return 1
  mkdir -p "$action_root" || return 1
  restore_state_acquire_lock "${action_root}/installer.lock" "$action_root" "installer.lock"
  case $? in
    0) ;;
    2) return 11 ;;
    *) return 1 ;;
  esac
  mkdir -p "${action_root}/tenants" || {
    restore_state_release_lock
    return 1
  }

  if [ -e "$tenant_root" ]; then
    if [ ! -f "$tenant_root/identity" ] || [ ! -f "$tenant_root/state" ]; then
      restore_state_release_lock
      echo "ERROR: incomplete restore intent for tenant ${tenant_name}" >&2
      return 1
    fi
    if ! grep -Fxq "tenant=${tenant_name}" "$tenant_root/identity" ||
      ! grep -Fxq "restoreUID=${KB_DP_RESTORE_UID}" "$tenant_root/identity" ||
      ! grep -Fxq "authNonce=${KB_DP_AUTHORIZATION_NONCE}" "$tenant_root/identity"; then
      restore_state_release_lock
      echo "ERROR: restore intent identity mismatch for tenant ${tenant_name}" >&2
      return 1
    fi
    restore_state_release_lock
    return 10
  fi

  if ! mkdir "$tenant_root"; then
    restore_state_release_lock
    return 1
  fi
  local identity_tmp="${tenant_root}/identity.tmp.$$"
  local state_tmp="${tenant_root}/state.tmp.$$"
  {
    printf 'tenant=%s\n' "$tenant_name"
    printf 'restoreUID=%s\n' "$KB_DP_RESTORE_UID"
    printf 'action=%s\n' "$KB_DP_RESTORE_ACTION"
    printf 'ordinal=%s\n' "$KB_DP_RESTORE_ACTION_ORDINAL"
    printf 'authGeneration=%s\n' "$KB_DP_AUTHORIZATION_GENERATION"
    printf 'authNonce=%s\n' "$KB_DP_AUTHORIZATION_NONCE"
  } >"$identity_tmp" || {
    restore_state_release_lock
    return 1
  }
  printf 'NO_REPLAY\n' >"$state_tmp" || {
    restore_state_release_lock
    return 1
  }
  mv "$identity_tmp" "$tenant_root/identity" &&
    mv "$state_tmp" "$tenant_root/state"
  local rc=$?
  restore_state_release_lock
  return "$rc"
}

restore_state_classify_tenant() {
  local status="$1"
  local role="$2"
  if [ -z "$status" ] && [ -z "$role" ]; then
    echo "ABSENT"
    return 0
  fi
  if [ "$status" = "RESTORE" ]; then
    echo "OBSERVE"
    return 0
  fi
  case "$role" in
    PRIMARY | STANDBY)
      echo "CLOSED"
      return 0
      ;;
  esac
  echo "ERROR: unexpected tenant state status=${status:-<empty>} role=${role:-<empty>}" >&2
  return 1
}
