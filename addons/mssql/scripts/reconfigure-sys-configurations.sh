#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -euo pipefail

CONFIG_FILE="${MSSQL_SYS_CONFIG_FILE:-/etc/sys-configurations/sys-configurations.toml}"
# Time budget: kbagent clamps a lifecycle action at 60s. This action probes the
# projected config exactly once and defers to runtime re-invocation when the
# target is not visible. Keep only the sqlcmd timeout budget at or below 50s so
# script setup and teardown retain 10s of headroom. The defaults are:
#   sqlcmd login timeout (-l, 10s)
# + sqlcmd query timeout (-t, 25s)
# = 35s.
MSSQL_SINGLE_SHOT_COMMAND_BUDGET=50
MSSQL_LOGIN_TIMEOUT="${MSSQL_LOGIN_TIMEOUT-10}"
MSSQL_QUERY_TIMEOUT="${MSSQL_QUERY_TIMEOUT-25}"

reconfigure_sys_configurations_diagnose() {
  local phase="$1"
  local ctx="$2"
  local retry_safe="$3"
  {
    echo "reconfigure-sys-configurations diagnosis:"
    echo "  action: reconfigure-sys-configurations"
    echo "  phase: ${phase}"
    echo "  cluster: ${KB_CLUSTER_NAME:-<unset>}"
    echo "  pod: ${KB_POD_NAME:-<unset>}"
    echo "${ctx}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

if [ -n "${SQLCMD:-}" ]; then
  if [ ! -f "${SQLCMD}" ] || [ ! -x "${SQLCMD}" ]; then
    reconfigure_sys_configurations_diagnose \
      "sqlcmd-override-invalid" \
      "  sqlcmd-override: ${SQLCMD}" \
      "no"
    exit 1
  fi
elif [ -x /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -x /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi

if [ ! -f "${CONFIG_FILE}" ]; then
  reconfigure_sys_configurations_diagnose \
    "config-file-missing" \
    "  config-file: ${CONFIG_FILE}" \
    "no"
  exit 1
fi

config_line_re="^[[:space:]]*'([^']+)'[[:space:]]*=[[:space:]]*(-?[0-9]+)[[:space:]]*(#.*)?$"

# Determine whether the projected config has converged to the change that
# triggered this reconfigure. KB main passes the changed parameter as $1 (key)
# and $2 (value) via kbagent Arguments (see
# addon-reconfigure-exec-parameter-passing-guide). The projection has converged
# iff the mounted config already contains that key = value.
#
# This is deterministic and independent of WHEN the projection happened: the
# controller may invoke this action seconds -- or, as observed, many minutes --
# after the projected volume settled. The previous heuristic ("..data mtime
# <= 10s" OR "content changes within a 15s window") could not recognise an
# already-settled projection, so a late controller invocation deferred forever
# and wedged the OpsRequest.
_target_key="${1:-}"
_target_value="${2:-}"
# Tolerate a quoted/padded argument so it still matches the bare toml key.
_target_key="${_target_key#\'}"; _target_key="${_target_key%\'}"
_target_key="$(printf '%s' "${_target_key}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# Read one snapshot of the mounted config and classify the key probe:
#   rc=0: key found, CONFIG_PROBE_VALUE is set
#   rc=1: file read succeeded, key is absent
#   rc=2: file read failed, CONFIG_READ_RC preserves the underlying cat rc
# Globals keep the snapshot and status in this shell; command substitution would
# run the function in a subshell and lose that distinction.
CONFIG_PROBE_CONTENT=""
CONFIG_PROBE_VALUE=""
CONFIG_READ_RC=0
config_value_of() {
  local want="$1" line k v
  CONFIG_PROBE_CONTENT=""
  CONFIG_PROBE_VALUE=""
  CONFIG_READ_RC=0
  if CONFIG_PROBE_CONTENT="$(cat -- "${CONFIG_FILE}" 2>/dev/null)"; then
    :
  else
    CONFIG_READ_RC=$?
    return 2
  fi
  while IFS= read -r line; do
    if [[ "${line}" =~ ${config_line_re} ]]; then
      k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
      if [ "${k}" = "${want}" ]; then
        CONFIG_PROBE_VALUE="${v}"
        return 0
      fi
    fi
  done <<< "${CONFIG_PROBE_CONTENT}"
  return 1
}

if [ -z "${_target_key}" ] || [ -z "${_target_value}" ]; then
  reconfigure_sys_configurations_diagnose \
    "target-args-missing" \
    "  config-file: ${CONFIG_FILE}
  note: reconfigure requires the changed parameter as \$1 (key) and \$2 (value); refusing to apply an unproven mounted config" \
    "no"
  exit 1
fi

normalize_nonnegative_action_timeout() {
  local value="$1"
  case "${value}" in
    ""|*[!0-9]*) return 1 ;;
  esac
  while [ "${value#0}" != "${value}" ]; do
    value="${value#0}"
  done
  [ -n "${value}" ] || value=0
  [ "${#value}" -le 2 ] || return 1
  printf '%s' "${value}"
}

normalize_positive_action_timeout() {
  local value
  value="$(normalize_nonnegative_action_timeout "$1")" || return 1
  [ "${value}" -ge 1 ] || return 1
  printf '%s' "${value}"
}

if ! MSSQL_LOGIN_TIMEOUT="$(normalize_positive_action_timeout "${MSSQL_LOGIN_TIMEOUT}")"; then
  reconfigure_sys_configurations_diagnose \
    "action-timeout-invalid" \
    "  invalid-variable: MSSQL_LOGIN_TIMEOUT
  requirement: positive finite decimal within the single-shot command budget" \
    "no"
  exit 1
fi
if ! MSSQL_QUERY_TIMEOUT="$(normalize_positive_action_timeout "${MSSQL_QUERY_TIMEOUT}")"; then
  reconfigure_sys_configurations_diagnose \
    "action-timeout-invalid" \
    "  invalid-variable: MSSQL_QUERY_TIMEOUT
  requirement: positive finite decimal within the single-shot command budget" \
    "no"
  exit 1
fi

_combined_timeout=$((MSSQL_LOGIN_TIMEOUT + MSSQL_QUERY_TIMEOUT))
if [ "${_combined_timeout}" -gt "${MSSQL_SINGLE_SHOT_COMMAND_BUDGET}" ]; then
  reconfigure_sys_configurations_diagnose \
    "action-timeout-invalid" \
    "  login-timeout: ${MSSQL_LOGIN_TIMEOUT}s
  query-timeout: ${MSSQL_QUERY_TIMEOUT}s
  combined-timeout: ${_combined_timeout}s
  maximum-command-budget: ${MSSQL_SINGLE_SHOT_COMMAND_BUDGET}s" \
    "no"
  exit 1
fi

if config_value_of "${_target_key}"; then
  _probe_rc=0
else
  _probe_rc=$?
fi
if [ "${_probe_rc}" -eq 2 ]; then
  reconfigure_sys_configurations_diagnose \
    "config-file-read-failed" \
    "  config-file: ${CONFIG_FILE}
  read-rc: ${CONFIG_READ_RC}" \
    "no"
  exit 1
fi
if [ "${_probe_rc}" -ne 0 ] && [ "${_probe_rc}" -ne 1 ]; then
  reconfigure_sys_configurations_diagnose \
    "projection-probe-failed" \
    "  config-file: ${CONFIG_FILE}
  probe-rc: ${_probe_rc}" \
    "no"
  exit 1
fi
_cur_value="${CONFIG_PROBE_VALUE}"
if [ "${_probe_rc}" -ne 0 ] || [ "${_cur_value}" != "${_target_value}" ]; then
  # expected vs observed are both printed so a key-format mismatch is obvious.
  reconfigure_sys_configurations_diagnose \
    "projection-target-not-visible" \
    "  config-file: ${CONFIG_FILE}
  expected: '${_target_key}' = ${_target_value}
  observed: '${_target_key}' = '${_cur_value:-<absent>}'" \
    "yes"
  exit 1
fi
_converged_config="${CONFIG_PROBE_CONTENT}"
echo "reconfigure: projected config has target '${_target_key}' = ${_target_value}; proceeding" >&2

: "${MSSQL_SERVER_PORT:=1433}"
if [ -z "${MSSQL_SA_USER:-}" ]; then
  reconfigure_sys_configurations_diagnose \
    "required-credential-env-missing" \
    "  missing-variable: MSSQL_SA_USER" \
    "no"
  exit 1
fi
if [ -z "${MSSQL_SA_PASSWORD:-}" ]; then
  reconfigure_sys_configurations_diagnose \
    "required-credential-env-missing" \
    "  missing-variable: MSSQL_SA_PASSWORD" \
    "no"
  exit 1
fi

sql_file="$(mktemp)"
sql_output_file="$(mktemp)"
expected_file="$(mktemp)"
trap 'rm -f "${sql_file}" "${sql_output_file}" "${expected_file}"' EXIT
phase_token="${sql_file##*/}"

cat > "${sql_file}" <<'SQL'
SET NOCOUNT ON;
-- Keep one sqlcmd call inside the lifecycle-action budget while preserving
-- whether an engine-side failure happened during mutation or verification.
DECLARE @kb_reconfigure_phase nvarchar(16) = N'apply';
BEGIN TRY
IF EXISTS (
  SELECT 1
  FROM sys.configurations
  WHERE name = N'show advanced options'
    AND TRY_CONVERT(bigint, value) <> 1
)
BEGIN
  EXEC sp_configure N'show advanced options', 1;
END
RECONFIGURE;
SQL

param_count=0
while IFS= read -r line || [ -n "${line}" ]; do
  trimmed="$(printf '%s' "${line}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -z "${trimmed}" ] || [ "${trimmed#\#}" != "${trimmed}" ]; then
    continue
  fi

  if [[ ! "${line}" =~ ${config_line_re} ]]; then
    reconfigure_sys_configurations_diagnose \
      "invalid-config-line" \
      "  config-file: ${CONFIG_FILE}
  line: ${line}" \
      "no"
    exit 1
  fi

  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  sql_key="$(printf '%s' "${key}" | sed "s/'/''/g")"

  cat >> "${sql_file}" <<SQL
IF EXISTS (
  SELECT 1
  FROM sys.configurations
  WHERE name = N'${sql_key}'
    AND TRY_CONVERT(bigint, value) <> ${value}
)
BEGIN
  EXEC sp_configure N'${sql_key}', ${value};
END
SQL
  printf '%s\t%s\n' "${sql_key}" "${value}" >> "${expected_file}"
  param_count=$((param_count + 1))
done <<< "${_converged_config}"

if [ "${param_count}" -eq 0 ]; then
  reconfigure_sys_configurations_diagnose \
    "no-parameters" \
    "  config-file: ${CONFIG_FILE}" \
    "no"
  exit 1
fi

cat >> "${sql_file}" <<'SQL'
RECONFIGURE;
SET @kb_reconfigure_phase = N'verify';
DECLARE @mismatches TABLE (
  name sysname NOT NULL,
  expected_value bigint NOT NULL,
  actual_value bigint NULL
);
SQL

# Verification is split on sys.configurations.is_dynamic:
# - is_dynamic = 1: sp_configure + RECONFIGURE takes effect immediately,
#   so verify the live value_in_use.
# - is_dynamic = 0: RECONFIGURE only records the new configured value;
#   value_in_use changes after instance restart. Verify the configured value
#   and emit a notice instead of failing forever on value_in_use.
while IFS=$'\t' read -r sql_key value || [ -n "${sql_key}" ]; do
  cat >> "${sql_file}" <<SQL
INSERT INTO @mismatches (name, expected_value, actual_value)
SELECT N'${sql_key}', ${value},
       CASE WHEN c.is_dynamic = 1
            THEN TRY_CONVERT(bigint, c.value_in_use)
            ELSE TRY_CONVERT(bigint, c.value)
       END
FROM (VALUES (1)) AS probe(n)
LEFT JOIN sys.configurations AS c ON c.name = N'${sql_key}'
WHERE c.name IS NULL
   OR (c.is_dynamic = 1 AND TRY_CONVERT(bigint, c.value_in_use) <> ${value})
   OR (c.is_dynamic = 0 AND TRY_CONVERT(bigint, c.value) <> ${value});
IF EXISTS (
  SELECT 1
  FROM sys.configurations
  WHERE name = N'${sql_key}'
    AND is_dynamic = 0
    AND TRY_CONVERT(bigint, value) = ${value}
    AND TRY_CONVERT(bigint, value_in_use) <> ${value}
)
BEGIN
  PRINT N'NOTICE: parameter ${sql_key} is static; new value recorded, takes effect after instance restart';
END
SQL
done < "${expected_file}"

cat >> "${sql_file}" <<'SQL'
IF EXISTS (SELECT 1 FROM @mismatches)
BEGIN
  SELECT name, expected_value, actual_value FROM @mismatches ORDER BY name;
  THROW 51000, 'mssql sys reconfigure verification failed', 1;
END
SQL
printf "PRINT N'KB_RECONFIGURE_SUCCESS=%s:verified';\n" \
  "${phase_token}" >> "${sql_file}"
cat >> "${sql_file}" <<'SQL'
SELECT 'mssql sys reconfigure applied and verified' AS result;
END TRY
BEGIN CATCH
SQL
printf "  PRINT N'KB_RECONFIGURE_PHASE=%s:' + @kb_reconfigure_phase;\n" \
  "${phase_token}" >> "${sql_file}"
cat >> "${sql_file}" <<'SQL'
  THROW;
END CATCH
SQL

if "${SQLCMD}" \
  -S "127.0.0.1,${MSSQL_SERVER_PORT}" \
  -U "${MSSQL_SA_USER}" \
  -P "${MSSQL_SA_PASSWORD}" \
  -C \
  -b \
  -r 1 \
  -l "${MSSQL_LOGIN_TIMEOUT}" \
  -t "${MSSQL_QUERY_TIMEOUT}" \
  -i "${sql_file}" > "${sql_output_file}" 2>&1; then
  success_marker="KB_RECONFIGURE_SUCCESS=${phase_token}:verified"
  if awk -v marker="${success_marker}" \
    '{ sub(/\r$/, ""); if ($0 == marker) found = 1 } END { exit !found }' \
    "${sql_output_file}"; then
    cat "${sql_output_file}"
  else
    cat "${sql_output_file}" >&2
    reconfigure_sys_configurations_diagnose \
      "sql-positive-verify-missing" \
      "  config-file: ${CONFIG_FILE}
  sqlcmd: ${SQLCMD}" \
      "no"
    exit 1
  fi
else
  cat "${sql_output_file}" >&2
  failure_phase="sql-command-failed"
  apply_marker="KB_RECONFIGURE_PHASE=${phase_token}:apply"
  verify_marker="KB_RECONFIGURE_PHASE=${phase_token}:verify"
  if awk -v marker="${apply_marker}" \
    '{ sub(/\r$/, ""); if ($0 == marker) found = 1 } END { exit !found }' \
    "${sql_output_file}"; then
    failure_phase="sql-apply-failed"
  elif awk -v marker="${verify_marker}" \
    '{ sub(/\r$/, ""); if ($0 == marker) found = 1 } END { exit !found }' \
    "${sql_output_file}"; then
    failure_phase="sql-verify-failed"
  fi
  reconfigure_sys_configurations_diagnose \
    "${failure_phase}" \
    "  config-file: ${CONFIG_FILE}
  sqlcmd: ${SQLCMD}" \
    "no"
  exit 1
fi
