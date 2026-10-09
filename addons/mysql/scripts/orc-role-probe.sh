#!/bin/bash

role_probe_error() {
  printf 'orc role probe failed: %s\n' "$*" >&2
  return 1
}

run_orc_role_probe() {
  local budget="${ORC_ROLE_PROBE_CLIENT_TIMEOUT_SECONDS:-4}"
  if command -v timeout >/dev/null 2>&1; then
    timeout "${budget}s" /kubeblocks/orchestrator-client "$@"
    return $?
  fi

  local temp_dir output_file error_file timeout_file pid timer_pid rc
  temp_dir=$(mktemp -d /tmp/orc-role-probe.XXXXXX) || return 1
  output_file="${temp_dir}/output"
  error_file="${temp_dir}/error"
  timeout_file="${temp_dir}/timeout"
  /kubeblocks/orchestrator-client "$@" > "${output_file}" 2> "${error_file}" &
  pid=$!
  (
    sleep "${budget}"
    if kill -0 "${pid}" 2>/dev/null; then
      printf 'timeout\n' > "${timeout_file}"
      kill "${pid}" 2>/dev/null || true
      sleep 1
      kill -9 "${pid}" 2>/dev/null || true
    fi
  ) &
  timer_pid=$!

  wait "${pid}" 2>/dev/null
  rc=$?
  kill "${timer_pid}" 2>/dev/null || true
  wait "${timer_pid}" 2>/dev/null || true
  cat "${output_file}" 2>/dev/null || true
  cat "${error_file}" >&2 2>/dev/null || true
  if [ -s "${timeout_file}" ]; then
    rc=124
  fi
  rm -rf "${temp_dir}"
  return "${rc}"
}

probe_orchestrator_role() {
  local master_info master_from_orc replicas replica rc

  master_info=$(run_orc_role_probe -c which-cluster-master -i "${KB_AGENT_POD_NAME}")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    role_probe_error "cannot determine master (rc=${rc})"
    return 1
  fi
  if [ -z "$master_info" ]; then
    role_probe_error "master query returned empty output"
    return 1
  fi

  master_from_orc="${master_info%%:*}"
  if [ "$master_from_orc" = "${KB_AGENT_POD_NAME}" ]; then
    printf 'primary'
    return 0
  fi

  replicas=$(run_orc_role_probe -c which-cluster-instances -i "${master_from_orc}")
  rc=$?
  if [ "$rc" -ne 0 ]; then
    role_probe_error "cannot list replicas for ${master_from_orc} (rc=${rc})"
    return 1
  fi
  for replica in $replicas; do
    if [ "${replica%%:*}" = "${KB_AGENT_POD_NAME}" ]; then
      printf 'secondary'
      return 0
    fi
  done

  role_probe_error "pod ${KB_AGENT_POD_NAME} is absent from Orchestrator topology rooted at ${master_from_orc}"
  return 1
}

# ShellSpec sets __SOURCED__; load functions without executing the probe.
${__SOURCED__:+false} : || return 0

probe_orchestrator_role
