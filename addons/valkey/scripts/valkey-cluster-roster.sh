#!/bin/bash

# Parse the public combined-variable contract:
#   shard-name=fqdn1,fqdn2;other-shard=fqdn3,fqdn4
# Output is sorted "shard-name fqdn1,fqdn2" records.
parse_shard_fqdn_map() {
  local raw="${ALL_SHARDS_POD_FQDN_MAP:-}" entry shard fqdns
  local expected_raw="${ALL_SHARDS_COMPONENT_SHORT_NAMES:-}" expected_entry expected_shard
  local expected="|" seen="|" seen_fqdns="|" output="" fqdn
  local expected_count=0 map_count=0
  local entries=() expected_entries=() _fqdns=()

  if [ -z "${raw}" ]; then
    classify shard-roster no "ALL_SHARDS_POD_FQDN_MAP is empty (roster unknown)"
    return 1
  fi
  if [ -z "${expected_raw}" ]; then
    classify shard-roster no "ALL_SHARDS_COMPONENT_SHORT_NAMES is empty (roster identity unknown)"
    return 1
  fi
  IFS=',' read -ra expected_entries <<< "${expected_raw}"
  for expected_entry in "${expected_entries[@]}"; do
    case "${expected_entry}" in
      *:*) expected_shard="${expected_entry%%:*}" ;;
      *)
        classify shard-roster no "malformed ALL_SHARDS_COMPONENT_SHORT_NAMES entry '${expected_entry}'"
        return 1 ;;
    esac
    if [ -z "${expected_shard}" ]; then
      classify shard-roster no "empty shard key in ALL_SHARDS_COMPONENT_SHORT_NAMES"
      return 1
    fi
    case "${expected}" in
      *"|${expected_shard}|"*)
        classify shard-roster no "duplicate shard ${expected_shard} in ALL_SHARDS_COMPONENT_SHORT_NAMES"
        return 1 ;;
    esac
    expected="${expected}${expected_shard}|"
    expected_count=$((expected_count + 1))
  done
  case "${raw}" in
    ';'*|*';'|*';;'*)
      classify shard-roster no "ALL_SHARDS_POD_FQDN_MAP has an empty shard entry"
      return 1 ;;
  esac
  IFS=';' read -ra entries <<< "${raw}"
  for entry in "${entries[@]}"; do
    case "${entry}" in
      *=*) ;;
      *)
        classify shard-roster no "malformed ALL_SHARDS_POD_FQDN_MAP entry '${entry}'"
        return 1 ;;
    esac
    shard="${entry%%=*}"
    fqdns="${entry#*=}"
    if [ -z "${shard}" ] || ! printf '%s\n' "${shard}" |
      grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'; then
      classify shard-roster no "invalid shard name '${shard}' in ALL_SHARDS_POD_FQDN_MAP"
      return 1
    fi
    case "${fqdns}" in
      ''|*=*|','*|*','|*',,'*)
        classify shard-roster no "shard ${shard} has an invalid or empty FQDN list"
        return 1 ;;
    esac
    case "${seen}" in
      *"|${shard}|"*)
        classify shard-roster no "duplicate shard ${shard} in ALL_SHARDS_POD_FQDN_MAP"
        return 1 ;;
    esac
    case "${expected}" in
      *"|${shard}|"*) ;;
      *)
        classify shard-roster no "unexpected shard ${shard} in ALL_SHARDS_POD_FQDN_MAP"
        return 1 ;;
    esac
    seen="${seen}${shard}|"
    map_count=$((map_count + 1))
    IFS=',' read -ra _fqdns <<< "${fqdns}"
    for fqdn in "${_fqdns[@]}"; do
      if [ -z "${fqdn}" ] || ! printf '%s\n' "${fqdn}" |
        grep -Eq '^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$'; then
        classify shard-roster no "shard ${shard} has malformed FQDN '${fqdn}'"
        return 1
      fi
      case "${seen_fqdns}" in
        *"|${fqdn}|"*)
          classify shard-roster no "duplicate FQDN ${fqdn} in ALL_SHARDS_POD_FQDN_MAP"
          return 1 ;;
      esac
      seen_fqdns="${seen_fqdns}${fqdn}|"
    done
    output="${output}${shard} ${fqdns}"$'\n'
  done
  if [ "${map_count}" -ne "${expected_count}" ]; then
    classify shard-roster no "ALL_SHARDS_POD_FQDN_MAP is incomplete: expected ${expected_count} shards, got ${map_count}"
    return 1
  fi
  printf '%s' "${output}" | LC_ALL=C sort
}
