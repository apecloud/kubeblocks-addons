#!/bin/sh
# Validate replication-mode source-of-truth consistency for the merged
# MariaDB CmpD (alpha.89 v1 commit 4, Helen 2026-05-19, C1 path).
#
# Two-source check (the two sources that exist in the C1 design; the
# v3.1 design rationale §3 deferred the optional third source — a
# Cluster annotation — to a future controller-side writer):
#
#   1. Engine SQL: SHOW VARIABLES LIKE 'rpl_semi_sync_master_enabled'
#      and 'rpl_semi_sync_slave_enabled' — the actual in-memory state
#      of mariadbd. After alpha.88 persistence this also matches
#      what mariadbd will read on next process restart.
#
#   2. ComponentParameter view via the kbagent-mounted ConfigMap
#      file (/etc/mysql/conf.d/my.cnf or the chart-rendered path) —
#      what KB merged for this cluster from PD schema defaults and
#      user-provided spec.componentSpecs[].parameters values. This
#      represents the desired state after the Configure controller
#      has reconciled.
#
# Read-only by design (Jack design review Gate 5 v3 — annotation
# writes are deferred). This script never writes engine state or
# Kubernetes resources; it only diffs the two sources and reports.
# Tests / runners call it at closeout to fail-closed when the two
# sources disagree (which means either reconfigure has not yet
# propagated or a stuck merge happened).
#
# Exit codes:
#   0 — both sources observable and consistent
#   1 — sources disagree (closeout FAIL)
#   2 — could not read engine state (transient; test should bounded-retry)
#   3 — could not read ConfigMap state (transient; test should bounded-retry)
#   4 — invariant violated (e.g. master_enabled=ON but slave_enabled=OFF on
#       a secondary pod, which mariadb semisync requires to be aligned)
#
# Output format on stdout (one JSON object per line is reserved for
# future machine consumption; v1 uses simple key=value tokens so a
# kbagent action attestation or shell test can grep them):
#
#   mode_engine_master_enabled=ON
#   mode_engine_slave_enabled=ON
#   mode_configmap_master_enabled=ON
#   mode_configmap_slave_enabled=ON
#   mode_consistency=ok|disagree|engine_missing|configmap_missing|invariant_violated
#
# /bin/sh shebang per addon convention (kbagent ships busybox sh).

set -u

EXIT_OK=0
EXIT_DISAGREE=1
EXIT_ENGINE_MISSING=2
EXIT_CONFIGMAP_MISSING=3
EXIT_INVARIANT_VIOLATED=4

CONFIG_PATH="${MARIADB_CONFIG_PATH:-/etc/mysql/conf.d/my.cnf}"
MYSQL_HOST="${MARIADB_HOST:-127.0.0.1}"
MYSQL_PORT="${MARIADB_PORT:-3306}"

# Engine connection context. None are required to run; if a value is
# unset the corresponding mysql client flag is simply not added. This
# pre-stages the env surface a kbagent lifecycle action will need
# without forcing the helper to know how the action resolves them
# (typically MYSQL_USER + MYSQL_PASSWORD + MYSQL_SOCKET are mounted
# from a Secret + the chart's mysqld socket path; the existing
# semisync lifecycle scripts already follow this pattern).
# alpha.89 v1 commit 4 v2 (Helen 2026-05-19, Jack review B2): add the
# env passthroughs so a later commit that wires this helper into a
# lifecycle action does not have to re-touch the helper itself.
MYSQL_SOCKET="${MYSQL_SOCKET:-}"
MYSQL_USER="${MYSQL_USER:-}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}"
MYSQL_EXTRA_ARGS="${MYSQL_EXTRA_ARGS:-}"

# Get the in-memory engine variable. Echoes the value on stdout and
# returns 0 on success; returns non-zero on any client error so the
# caller can distinguish "engine not reachable" from "engine reachable
# but returned empty value" (which also returns non-zero to keep the
# fail-closed semantics uniform across the four variables).
engine_var() {
  var_name="$1"
  # MariaDB client is mysql; use --batch --skip-column-names so output
  # is the value alone. Connect via the local socket if available to
  # avoid TLS/auth overhead during local introspection.
  mysql_args="--batch --skip-column-names --connect-timeout=3"
  if [ -n "${MYSQL_SOCKET}" ]; then
    mysql_args="${mysql_args} -S ${MYSQL_SOCKET}"
  else
    mysql_args="${mysql_args} -h${MYSQL_HOST} -P${MYSQL_PORT}"
  fi
  if [ -n "${MYSQL_USER}" ]; then
    mysql_args="${mysql_args} -u${MYSQL_USER}"
  fi
  if [ -n "${MYSQL_PASSWORD}" ]; then
    mysql_args="${mysql_args} -p${MYSQL_PASSWORD}"
  fi
  if [ -n "${MYSQL_EXTRA_ARGS}" ]; then
    mysql_args="${mysql_args} ${MYSQL_EXTRA_ARGS}"
  fi
  # shellcheck disable=SC2086 # word-splitting is intentional
  out=$(mysql ${mysql_args} -e "SHOW VARIABLES LIKE '${var_name}'" 2>/dev/null) || return 1
  # Output line shape: "<var_name>\t<value>". Print only the value
  # and surface an empty result as a non-zero return so the caller
  # uniformly treats a successful-but-empty read as missing.
  val=$(printf '%s' "${out}" | awk -F'\t' 'NR==1 {print $2}')
  if [ -z "${val}" ]; then
    return 1
  fi
  printf '%s' "${val}"
}

# Read a single key from the ConfigMap-mounted my.cnf. Echoes the
# value and returns 0 on success; returns non-zero if the file is
# unreadable or the key is missing. Treating "key missing" as
# non-zero matches engine_var's contract: callers do not have to
# inspect both the rc and an empty string.
configmap_var() {
  var_name="$1"
  if [ ! -r "${CONFIG_PATH}" ]; then
    return 1
  fi
  val=$(awk -v key="${var_name}" '
    # match key with optional surrounding whitespace; both key in the
    # config file and key argument are lowercased before comparison.
    /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/ {
      n = split($0, a, "=")
      k = a[1]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (tolower(k) == tolower(key)) {
        v = a[2]
        for (i = 3; i <= n; i++) v = v "=" a[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        sub(/[[:space:]]*#.*$/, "", v)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "${CONFIG_PATH}")
  if [ -z "${val}" ]; then
    return 1
  fi
  printf '%s' "${val}"
}

# Normalize a MariaDB boolean value to a canonical ON/OFF form so
# ConfigMap (which the chart writes as ON/OFF) and engine (which
# accepts ON/OFF/1/0) can be compared. Returns the original value
# unchanged if it is not a recognized boolean — non-recognized
# values surface as a comparison miss, which the caller treats as
# a disagreement.
normalize_bool() {
  v="$1"
  case "$(printf '%s' "${v}" | tr '[:upper:]' '[:lower:]')" in
    on|true|1)  printf 'ON' ;;
    off|false|0) printf 'OFF' ;;
    *) printf '%s' "${v}" ;;
  esac
}

# Read both engine variables and capture the rc of each individually.
# alpha.89 v1 commit 4 v2 (Helen 2026-05-19, Jack review B1): the
# v1 check only inspected master's rc, so a slave read failure
# silently fell through and ended up classified as
# `invariant_violated` (when master=ON) or `disagree`, instead of
# the correct `engine_missing` / `configmap_missing` signals. Treat
# missing OR unreadable on either side as the same observability
# failure as if the other side were missing.
eng_master=$(engine_var rpl_semi_sync_master_enabled)
eng_master_rc=$?
eng_slave=$(engine_var rpl_semi_sync_slave_enabled)
eng_slave_rc=$?
cm_master=$(configmap_var rpl_semi_sync_master_enabled)
cm_master_rc=$?
cm_slave=$(configmap_var rpl_semi_sync_slave_enabled)
cm_slave_rc=$?

if [ "${eng_master_rc}" -ne 0 ] || [ "${eng_slave_rc}" -ne 0 ]; then
  printf 'mode_engine_master_enabled=%s\n' "${eng_master:-}"
  printf 'mode_engine_slave_enabled=%s\n' "${eng_slave:-}"
  printf 'mode_configmap_master_enabled=%s\n' "${cm_master:-}"
  printf 'mode_configmap_slave_enabled=%s\n' "${cm_slave:-}"
  printf 'mode_consistency=engine_missing\n'
  exit "${EXIT_ENGINE_MISSING}"
fi

if [ "${cm_master_rc}" -ne 0 ] || [ "${cm_slave_rc}" -ne 0 ]; then
  printf 'mode_engine_master_enabled=%s\n' "${eng_master}"
  printf 'mode_engine_slave_enabled=%s\n' "${eng_slave}"
  printf 'mode_configmap_master_enabled=%s\n' "${cm_master:-}"
  printf 'mode_configmap_slave_enabled=%s\n' "${cm_slave:-}"
  printf 'mode_consistency=configmap_missing\n'
  exit "${EXIT_CONFIGMAP_MISSING}"
fi

eng_master_n=$(normalize_bool "${eng_master}")
eng_slave_n=$(normalize_bool "${eng_slave}")
cm_master_n=$(normalize_bool "${cm_master}")
cm_slave_n=$(normalize_bool "${cm_slave}")

# Invariant: when master=ON the slave side must also be ON for
# semisync to actually engage on this pair (MariaDB requires both
# variables aligned across the topology; an asymmetric ON/OFF pair
# silently degrades to async without an error).
if [ "${eng_master_n}" = "ON" ] && [ "${eng_slave_n}" != "ON" ]; then
  printf 'mode_engine_master_enabled=%s\n' "${eng_master_n}"
  printf 'mode_engine_slave_enabled=%s\n' "${eng_slave_n}"
  printf 'mode_configmap_master_enabled=%s\n' "${cm_master_n}"
  printf 'mode_configmap_slave_enabled=%s\n' "${cm_slave_n}"
  printf 'mode_consistency=invariant_violated\n'
  exit "${EXIT_INVARIANT_VIOLATED}"
fi

if [ "${eng_master_n}" = "${cm_master_n}" ] && [ "${eng_slave_n}" = "${cm_slave_n}" ]; then
  printf 'mode_engine_master_enabled=%s\n' "${eng_master_n}"
  printf 'mode_engine_slave_enabled=%s\n' "${eng_slave_n}"
  printf 'mode_configmap_master_enabled=%s\n' "${cm_master_n}"
  printf 'mode_configmap_slave_enabled=%s\n' "${cm_slave_n}"
  printf 'mode_consistency=ok\n'
  exit "${EXIT_OK}"
fi

printf 'mode_engine_master_enabled=%s\n' "${eng_master_n}"
printf 'mode_engine_slave_enabled=%s\n' "${eng_slave_n}"
printf 'mode_configmap_master_enabled=%s\n' "${cm_master_n}"
printf 'mode_configmap_slave_enabled=%s\n' "${cm_slave_n}"
printf 'mode_consistency=disagree\n'
exit "${EXIT_DISAGREE}"
