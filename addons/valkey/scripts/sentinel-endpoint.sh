#!/bin/bash

canonical_data_pod_fqdns() {
  local raw fqdn known candidate="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"
  local unique=()
  local found=0

  case "${VALKEY_POD_FQDN_LIST:-}" in
    ""|,*|*,|*,,*) return 1 ;;
  esac
  IFS=',' read -ra raw <<< "${VALKEY_POD_FQDN_LIST}"
  for fqdn in "${raw[@]}"; do
    [ -n "${fqdn}" ] || return 1
    for known in "${unique[@]}"; do
      [ "${known}" != "${fqdn}" ] || return 1
      [ "${known%%.*}" != "${fqdn%%.*}" ] || return 1
    done
    unique+=("${fqdn}")
  done

  if [ -n "${candidate}" ]; then
    case "${candidate}" in
      *,*) return 1 ;;
    esac
    for known in "${unique[@]}"; do
      if [ "${known}" = "${candidate}" ]; then
        found=1
        break
      fi
      [ "${known%%.*}" != "${candidate%%.*}" ] || return 1
    done
    [ "${found}" -eq 1 ] || unique+=("${candidate}")
  fi

  printf '%s\n' "${unique[@]}"
}

roster_fqdn_for_ordinal() {
  local expected_ordinal="$1"
  local roster fqdn ordinal
  local matches=()

  roster=$(canonical_data_pod_fqdns) || return 1
  while IFS= read -r fqdn; do
    [ -n "${fqdn}" ] || continue
    ordinal=$(extract_obj_ordinal "${fqdn%%.*}") || return 1
    [ -n "${ordinal}" ] || return 1
    [ "${ordinal}" = "${expected_ordinal}" ] && matches+=("${fqdn}")
  done <<< "${roster}"
  [ "${#matches[@]}" -eq 1 ] || return 1
  printf '%s\n' "${matches[0]}"
}

load_balancer_fqdn_for_host() {
  local endpoint_host="$1"
  local raw entry service_name value ordinal fqdn known found
  local port_services=()
  local host_services=()
  local host_values=()
  local matches=()

  [ -n "${VALKEY_LB_ADVERTISED_PORT:-}" ] &&
    [ -n "${VALKEY_LB_ADVERTISED_HOST:-}" ] || return 1
  case "${VALKEY_LB_ADVERTISED_PORT}" in
    ,*|*,|*,,*) return 1 ;;
  esac
  case "${VALKEY_LB_ADVERTISED_HOST}" in
    ,*|*,|*,,*) return 1 ;;
  esac

  IFS=',' read -ra raw <<< "${VALKEY_LB_ADVERTISED_PORT}"
  for entry in "${raw[@]}"; do
    case "${entry}" in
      *:*) ;;
      *) return 1 ;;
    esac
    service_name="${entry%%:*}"
    value="${entry#*:}"
    [ -n "${service_name}" ] && [ -n "${value}" ] || return 1
    case "${value}" in
      *:*|*[!0-9]*) return 1 ;;
    esac
    for known in "${port_services[@]}"; do
      [ "${known}" != "${service_name}" ] || return 1
    done
    port_services+=("${service_name}")
  done

  IFS=',' read -ra raw <<< "${VALKEY_LB_ADVERTISED_HOST}"
  for entry in "${raw[@]}"; do
    case "${entry}" in
      *:*) ;;
      *) return 1 ;;
    esac
    service_name="${entry%%:*}"
    value="${entry#*:}"
    [ -n "${service_name}" ] && [ -n "${value}" ] || return 1
    for known in "${host_services[@]}"; do
      [ "${known}" != "${service_name}" ] || return 1
    done
    for known in "${host_values[@]}"; do
      [ "${known}" != "${value}" ] || return 1
    done
    host_services+=("${service_name}")
    host_values+=("${value}")

    found=0
    for known in "${port_services[@]}"; do
      if [ "${known}" = "${service_name}" ]; then
        found=1
        break
      fi
    done
    [ "${found}" -eq 1 ] || return 1

    if [ "${value}" = "${endpoint_host}" ]; then
      ordinal=$(extract_obj_ordinal "${service_name}") || return 1
      [ -n "${ordinal}" ] || return 1
      fqdn=$(roster_fqdn_for_ordinal "${ordinal}") || return 1
      matches+=("${fqdn}")
    fi
  done

  [ "${#port_services[@]}" -eq "${#host_services[@]}" ] || return 1
  [ "${#matches[@]}" -gt 0 ] || return 2
  [ "${#matches[@]}" -eq 1 ] || return 1
  printf '%s\n' "${matches[0]}"
}

action_candidate_fqdn_for_announced_endpoint() {
  local endpoint_host="$1" endpoint_port="$2"
  local candidate="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"
  local output announced_host announced_port extra roster fqdn found=0

  [ -n "${candidate}" ] || return 2
  [ "$(type -t read_action_candidate_announced_endpoint 2>/dev/null)" = "function" ] || return 2
  output=$(read_action_candidate_announced_endpoint "${candidate}") || return 2
  output="${output//$'\r'/}"
  announced_host=$(printf '%s\n' "${output}" | sed -n '1p')
  announced_port=$(printf '%s\n' "${output}" | sed -n '2p')
  extra=$(printf '%s\n' "${output}" | sed -n '3p')
  [ -n "${announced_host}" ] && [ -n "${announced_port}" ] && [ -z "${extra}" ] || return 2
  case "${announced_port}" in
    *[!0-9]*) return 2 ;;
  esac
  [ "${announced_host}" = "${endpoint_host}" ] &&
    [ "${announced_port}" = "${endpoint_port}" ] || return 2

  roster=$(canonical_data_pod_fqdns) || return 1
  while IFS= read -r fqdn; do
    [ "${fqdn}" != "${candidate}" ] || found=$(( found + 1 ))
  done <<< "${roster}"
  [ "${found}" -eq 1 ] || return 1
  printf '%s\n' "${candidate}"
}

# Sentinel stores the address announced by Valkey. NodePort uses
# nodeIP:NodePort and LoadBalancer uses externalHost:servicePort, while
# lifecycle actions must use the internal pod FQDN and service port.
# Normalize every vote before quorum counting.
resolve_sentinel_master_endpoint() {
  local host="$1" reported_port="$2" mode="${3:-strict}"
  local internal_port="${SERVICE_PORT:-6379}"
  local raw entry service_name advertised_port ordinal fqdn
  local lb_fqdn lb_status action_fqdn action_status
  local matches=()

  [ -n "${host}" ] && [ "${host}" != "(nil)" ] || return 1
  case "${reported_port}" in
    ""|*[!0-9]*) return 1 ;;
  esac
  case "${mode}" in
    strict|member-leave|allow-external) ;;
    *) return 1 ;;
  esac

  if [ -n "${VALKEY_ADVERTISED_PORT:-}" ]; then
    case "${VALKEY_ADVERTISED_PORT}" in
      ,*|*,|*,,*) return 1 ;;
    esac
    IFS=',' read -ra raw <<< "${VALKEY_ADVERTISED_PORT}"
    for entry in "${raw[@]}"; do
      case "${entry}" in
        *:*) ;;
        *) return 1 ;;
      esac
      service_name="${entry%%:*}"
      advertised_port="${entry#*:}"
      [ -n "${service_name}" ] && [ -n "${advertised_port}" ] || return 1
      case "${advertised_port}" in
        *:*|*[!0-9]*) return 1 ;;
      esac
      [ "${advertised_port}" = "${reported_port}" ] || continue
      ordinal=$(extract_obj_ordinal "${service_name}") || return 1
      [ -n "${ordinal}" ] || return 1
      fqdn=$(roster_fqdn_for_ordinal "${ordinal}") || return 1
      matches+=("${fqdn}")
    done
    if [ "${#matches[@]}" -gt 0 ]; then
      [ "${#matches[@]}" -eq 1 ] || return 1
      printf '%s\n' "${matches[0]}"
      return 0
    fi
  fi

  if [ -n "${VALKEY_LB_ADVERTISED_PORT:-}" ] ||
     [ -n "${VALKEY_LB_ADVERTISED_HOST:-}" ]; then
    [ -z "${VALKEY_ADVERTISED_PORT:-}" ] || return 1
    [ "${reported_port}" = "${internal_port}" ] || return 1
    if lb_fqdn=$(load_balancer_fqdn_for_host "${host}"); then
      printf '%s\n' "${lb_fqdn}"
      return 0
    else
      lb_status=$?
      [ "${lb_status}" -eq 2 ] || return 1
    fi
    [ "${mode}" != "member-leave" ] || return 1
  fi

  if action_fqdn=$(action_candidate_fqdn_for_announced_endpoint "${host}" "${reported_port}"); then
    printf '%s\n' "${action_fqdn}"
    return 0
  else
    action_status=$?
    [ "${action_status}" -eq 2 ] || return 1
  fi

  if [ "${reported_port}" = "${internal_port}" ]; then
    if [ "${mode}" = "member-leave" ]; then
      if [ "${host}" = "${KB_LEAVE_MEMBER_POD_FQDN:-}" ] || \
         [ "${host}" = "${KB_LEAVE_MEMBER_POD_NAME:-}" ] || \
         { [ -n "${leaving_ip:-}" ] && [ "${host}" = "${leaving_ip}" ]; }; then
        printf '%s\n' "${KB_LEAVE_MEMBER_POD_FQDN}"
        return 0
      fi
      printf '%s\n' "${host}"
      return 0
    fi

    local roster
    local candidate pod_ip
    roster=$(canonical_data_pod_fqdns) || return 1
    matches=()
    while IFS= read -r candidate; do
      [ -n "${candidate}" ] || continue
      if [ "${host}" = "${candidate}" ] || [ "${host}" = "${candidate%%.*}" ]; then
        matches+=("${candidate}")
        continue
      fi
      pod_ip=$(getent hosts "${candidate}" 2>/dev/null | awk '{print $1}' | head -n1) || true
      [ -z "${pod_ip}" ] || [ "${host}" != "${pod_ip}" ] || matches+=("${candidate}")
    done <<< "${roster}"
    if [ "${#matches[@]}" -eq 1 ]; then
      printf '%s\n' "${matches[0]}"
      return 0
    fi
    [ "${#matches[@]}" -eq 0 ] || return 1
  else
    [ "${mode}" != "member-leave" ] || return 1
    canonical_data_pod_fqdns >/dev/null || return 1
  fi

  # With no requested candidate, a newly scaled replica may be absent from
  # creation-time advertised-endpoint metadata. Preserve the exact endpoint
  # identity so the caller can require both Sentinel majority and a direct
  # role readback without guessing an internal pod identity.
  if [ "${mode}" = "allow-external" ]; then
    case "${host}" in
      *'|'*) return 1 ;;
    esac
    printf '@sentinel-external|%s|%s\n' "${host}" "${reported_port}"
    return 0
  fi
  return 1
}
