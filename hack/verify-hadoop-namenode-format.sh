#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

SCRIPT_PATH="${ROOT_DIR}/addons/hadoop/scripts/init-namenode-format.sh"

make_mock_hdfs() {
  local bin_dir="$1"
  cat > "${bin_dir}/hdfs" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cmd="${1:-}"
shift || true

case "${cmd}" in
  getconf)
    if [[ "${1:-}" != "-confKey" ]]; then
      exit 2
    fi
    case "${2:-}" in
      dfs.namenode.name.dir)
        printf '%s\n' "${MOCK_NAME_DIRS:-}"
        ;;
      dfs.nameservices)
        printf '%s\n' "${MOCK_NAMESERVICES:-}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  namenode)
    if [[ "${1:-}" != "-format" ]]; then
      exit 2
    fi
    if [[ "${MOCK_FORMAT_RESULT:-success}" == "fail" ]]; then
      exit 1
    fi
    printf 'formatted\n'
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "${bin_dir}/hdfs"
}

make_mock_sleep() {
  local bin_dir="$1"
  cat > "${bin_dir}/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${bin_dir}/sleep"
}

# 功能：执行 init-namenode-format.sh，并断言 format 失败会向上传递。
# 参数：无，依赖临时 mock hdfs/sleep 和环境变量。
# 返回值：成功返回 0，失败返回非 0。
verify_format_failure_is_not_suppressed() {
  local case_dir bin_dir hadoop_home output
  case_dir="${TMP_DIR}/failure"
  bin_dir="${case_dir}/bin"
  hadoop_home="${case_dir}/hadoop"
  mkdir -p "${bin_dir}" "${hadoop_home}/bin" "${case_dir}/data"
  make_mock_hdfs "${hadoop_home}/bin"
  make_mock_sleep "${bin_dir}"

  if output="$(
    PATH="${bin_dir}:${PATH}" \
    HADOOP_HOME="${hadoop_home}" \
    POD_NAME="hdfs-namenode-0" \
    MOCK_NAME_DIRS="file://${case_dir}/data" \
    MOCK_NAMESERVICES="ns1" \
    MOCK_FORMAT_RESULT="fail" \
    bash "${SCRIPT_PATH}" 2>&1
  )"; then
    echo "expected init-namenode-format.sh to fail when format fails" >&2
    echo "${output}" >&2
    return 1
  fi
}

# 功能：执行 init-namenode-format.sh，并断言已有 fsimage 时会幂等跳过。
# 参数：无，依赖临时 mock hdfs/sleep 和环境变量。
# 返回值：成功返回 0，失败返回非 0。
verify_existing_fsimage_skips_format() {
  local case_dir bin_dir hadoop_home current_dir output
  case_dir="${TMP_DIR}/existing-fsimage"
  bin_dir="${case_dir}/bin"
  hadoop_home="${case_dir}/hadoop"
  current_dir="${case_dir}/data/current"
  mkdir -p "${bin_dir}" "${hadoop_home}/bin" "${current_dir}"
  touch "${current_dir}/fsimage_0000000000000000001"
  make_mock_hdfs "${hadoop_home}/bin"
  make_mock_sleep "${bin_dir}"

  output="$(
    PATH="${bin_dir}:${PATH}" \
    HADOOP_HOME="${hadoop_home}" \
    POD_NAME="hdfs-namenode-0" \
    MOCK_NAME_DIRS="file://${case_dir}/data" \
    MOCK_NAMESERVICES="ns1" \
    bash "${SCRIPT_PATH}" 2>&1
  )"

  grep -Fq "Valid fsimage already exists, skipping format" <<< "${output}" || {
    echo "expected script to skip format when fsimage already exists" >&2
    echo "${output}" >&2
    return 1
  }
}

verify_format_failure_is_not_suppressed
verify_existing_fsimage_skips_format

echo "namenode format verification passed"
