# shellcheck shell=bash

# EngineOption sends comma-separated quoted paths. Depth 1 allows parent-only paths.
parse_selection() {
  local value=$1
  local depth=${2:-2}
  local path_pattern='^"([^"]+)"(/"([^"]+)")?(,|$)'
  parents=()
  children=()
  while [[ "$value" =~ $path_pattern ]]; do
    [[ "$depth" == 1 || -n "${BASH_REMATCH[3]}" ]] || return 1
    parents+=("${BASH_REMATCH[1]}")
    children+=("${BASH_REMATCH[3]}")
    if [[ -z "${BASH_REMATCH[4]}" ]]; then
      return 0
    fi
    value=${value#"${BASH_REMATCH[0]}"}
  done
  return 1
}

# Escape punctuation and control bytes in each path component. Escape '%' itself
# so a literal sequence such as '%2F' stays distinct from '/'.
encode_archive_name() {
  local LC_ALL=C name=$1 byte i
  # Avoid hidden directories and keep "." and ".." from becoming path segments.
  if [[ "$name" == .* ]]; then
    printf '%%2E'
    name=${name:1}
  fi
  for ((i = 0; i < ${#name}; i++)); do
    byte=${name:i:1}
    case "$byte" in
      [a-zA-Z0-9._-]|[$'\200'-$'\377']) printf '%s' "$byte" ;;
      *) printf '%%%02X' "'$byte" ;;
    esac
  done
}

decode_archive_name() {
  local LC_ALL=C name=$1 byte escape
  decoded_name=
  while [[ -n "$name" ]]; do
    if [[ "$name" == %* ]]; then
      escape=${name:1:2}
      [[ "$escape" =~ ^[0-9A-F]{2}$ && "$escape" != 00 ]] || return 1
      printf -v byte '%b' "\\x$escape"
      name=${name:3}
    else
      byte=${name:0:1}
      name=${name:1}
    fi
    decoded_name+=$byte
  done
  [[ -n "$decoded_name" ]]
}

cluster_archive_path() {
  local database retention
  database=$(encode_archive_name "$1")
  if [[ -z "$2" ]]; then
    printf 'selected/%s/db.lp.gz' "$database"
  else
    retention=$(encode_archive_name "$2")
    printf 'selected/%s/rp/%s/data.lp.gz' "$database" "$retention"
  fi
}
