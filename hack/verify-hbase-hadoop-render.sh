#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "missing expected content: $needle" >&2
    return 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "$needle" "$file"; then
    echo "unexpected content found: $needle" >&2
    return 1
  fi
}

assert_not_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    echo "path should not exist: $path" >&2
    return 1
  fi
}

prepare_chart() {
  local chart="$1"
  helm dependency build "$chart" --skip-refresh >/dev/null
}

# 功能：校验 datanode decommission 脚本能从 Name/Hostname 两种 report 形式中识别目标节点状态。
# 参数：无。
# 返回值：校验通过返回 0，失败返回非 0。
verify_hadoop_decommission_host_match() {
  export KUBERNETES_SERVICE_HOST="127.0.0.1"
  export KUBERNETES_SERVICE_PORT_HTTPS="443"

  awk '
    $0 == "case \"${1:-register}\" in" { exit }
    { print }
  ' "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" >"${TMP_DIR}/datanode-decommission-prefix.sh"
  # ponytail: 直接 source 脚本前缀复用现有 helper；如果将来 case 入口结构变化，再改成单独可 source 的库文件。
  source "${TMP_DIR}/datanode-decommission-prefix.sh"

  cat >"${TMP_DIR}/report-name-with-fqdn.txt" <<'EOF'
Name: 10.1.2.3:9866 (hdfs-datanode-1.hadoop-headless.default.svc.cluster.local)
Hostname: hdfs-datanode-1.hadoop-headless.default.svc.cluster.local
Decommission Status : Decommissioned
EOF

  cat >"${TMP_DIR}/report-hostname-only.txt" <<'EOF'
Name: 10.1.2.4:9866
Hostname: hdfs-datanode-2.hadoop-headless.default.svc.cluster.local
Decommission Status : Decommissioned
EOF

  extract_decommission_status_from_report \
    "${TMP_DIR}/report-name-with-fqdn.txt" \
    "hdfs-datanode-1.hadoop-headless.default.svc.cluster.local" \
    >"${TMP_DIR}/status.txt"
  status="$(<"${TMP_DIR}/status.txt")"
  [[ "${status}" == "Decommissioned" ]] || {
    echo "expected report with Name alias to resolve decommission status" >&2
    return 1
  }

  extract_decommission_status_from_report \
    "${TMP_DIR}/report-hostname-only.txt" \
    "hdfs-datanode-2.hadoop-headless.default.svc.cluster.local" \
    >"${TMP_DIR}/status.txt"
  status="$(<"${TMP_DIR}/status.txt")"
  [[ "${status}" == "Decommissioned" ]] || {
    echo "expected report with Hostname field to resolve decommission status" >&2
    return 1
  }
}

# Verifies JournalNode readiness requires a reachable JMX bean with a bound RPC address.
# Parameters: none.
# Returns: 0 when valid JMX succeeds and empty or unreachable JMX fails.
verify_journalnode_probe() {
  local case_dir="${TMP_DIR}/journalnode-probe"
  mkdir -p "${case_dir}/bin"
  cat >"${case_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
[[ "${MOCK_CURL_RESULT:-success}" == "success" ]] || exit 1
printf '%s\n' "${MOCK_JMX_RESPONSE:-}"
EOF
  chmod +x "${case_dir}/bin/curl"

  PATH="${case_dir}/bin:${PATH}" \
    MOCK_JMX_RESPONSE='{"beans":[{"HostAndPort":"journalnode-0:8485","ClusterIds":[]}]}' \
    bash "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh"

  if PATH="${case_dir}/bin:${PATH}" \
    MOCK_JMX_RESPONSE='{"beans":[{"HostAndPort":"","ClusterIds":[]}]}' \
    bash "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh"; then
    echo "expected JournalNode probe to reject an empty HostAndPort" >&2
    return 1
  fi

  if PATH="${case_dir}/bin:${PATH}" \
    MOCK_CURL_RESULT="fail" \
    bash "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh"; then
    echo "expected JournalNode probe to reject an unreachable JMX endpoint" >&2
    return 1
  fi
}

# Verifies RegionServer readiness performs the registration query only until a marker is written.
# Parameters: none.
# Returns: 0 when the first probe queries HBase and later probes reuse the marker.
verify_regionserver_readiness_marker() {
  local case_dir="${TMP_DIR}/regionserver-readiness"
  local counter_file="${case_dir}/hbase-calls"
  local marker_file="${case_dir}/pid/report-for-duty.ready"
  mkdir -p "${case_dir}/bin" "${case_dir}/hbase/bin" "${case_dir}/pid"
  cat >"${case_dir}/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"${case_dir}/hbase/bin/hbase" <<'EOF'
#!/usr/bin/env bash
printf 'call\n' >>"${MOCK_HBASE_COUNTER}"
printf '1 live servers\n  rs.example,16020,123456\n'
EOF
  chmod +x "${case_dir}/bin/curl" "${case_dir}/hbase/bin/hbase"

  PATH="${case_dir}/bin:${PATH}" \
    HBASE_HOME="${case_dir}/hbase" \
    HBASE_PID_DIR="${case_dir}/pid" \
    HBASE_REGIONSERVER_PORT="16020" \
    POD_FQDN="rs.example" \
    MOCK_HBASE_COUNTER="${counter_file}" \
    bash "${ROOT_DIR}/addons/hbase/scripts/check-hregionserver-ready.sh"

  [[ -f "${marker_file}" ]] || {
    echo "expected RegionServer readiness to persist a reportForDuty marker" >&2
    return 1
  }

  PATH="${case_dir}/bin:${PATH}" \
    HBASE_HOME="${case_dir}/hbase" \
    HBASE_PID_DIR="${case_dir}/pid" \
    HBASE_REGIONSERVER_PORT="16020" \
    POD_FQDN="rs.example" \
    MOCK_HBASE_COUNTER="${counter_file}" \
    bash "${ROOT_DIR}/addons/hbase/scripts/check-hregionserver-ready.sh"

  [[ "$(wc -l <"${counter_file}" | tr -d ' ')" == "1" ]] || {
    echo "expected RegionServer readiness to avoid repeated HBase Shell processes" >&2
    return 1
  }
}

# Verifies HBase startup only requires ZooKeeper TCP reachability.
# Parameters: none.
# Returns: 0 when HMaster and RegionServer startup pass with a TCP-only endpoint.
verify_hbase_zookeeper_tcp_gate() {
  local case_dir="${TMP_DIR}/hbase-zk-tcp-gate"
  local port_file="${case_dir}/port"
  mkdir -p "${case_dir}/hbase/bin" "${case_dir}/conf" "${case_dir}/logs" "${case_dir}/pid"
  cat >"${case_dir}/hbase/bin/hbase" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat >"${case_dir}/hbase/bin/hbase-daemon.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  : >"${case_dir}/conf/hbase-env.sh"
  chmod +x "${case_dir}/hbase/bin/hbase" "${case_dir}/hbase/bin/hbase-daemon.sh"

  perl -MIO::Socket::INET -e '
    my $port_file = shift @ARGV;
    my $server = IO::Socket::INET->new(
      LocalAddr => "127.0.0.1",
      LocalPort => 0,
      Proto => "tcp",
      Listen => 5,
      Reuse => 1,
    ) or die $!;
    open my $fh, ">", $port_file or die $!;
    print {$fh} $server->sockport();
    close $fh;
    while (my $client = $server->accept()) {
      my $request = "";
      sysread($client, $request, 1024);
      print {$client} "notimok\n";
      close $client;
    }
  ' "${port_file}" &
  local server_pid=$!
  trap 'kill "${server_pid}" >/dev/null 2>&1 || true' RETURN

  local zk_port
  for _ in {1..50}; do
    [[ -s "${port_file}" ]] && break
    sleep 0.1
  done
  zk_port="$(<"${port_file}")"

  HBASE_HOME="${case_dir}/hbase" \
    HBASE_CONF_DIR="${case_dir}/conf" \
    HBASE_LOG_DIR="${case_dir}/logs" \
    HBASE_PID_DIR="${case_dir}/pid" \
    ZOOKEEPER_ENDPOINTS="127.0.0.1:${zk_port}" \
    ZOOKEEPER_WAIT_TIMEOUT_SECONDS=2 \
    ZOOKEEPER_WAIT_INTERVAL_SECONDS=1 \
    bash "${ROOT_DIR}/addons/hbase/scripts/start-hmaster.sh"

  HBASE_HOME="${case_dir}/hbase" \
    HBASE_CONF_DIR="${case_dir}/conf" \
    HBASE_LOG_DIR="${case_dir}/logs" \
    HBASE_PID_DIR="${case_dir}/pid" \
    ZOOKEEPER_ENDPOINTS="127.0.0.1:${zk_port}" \
    ZOOKEEPER_WAIT_TIMEOUT_SECONDS=2 \
    ZOOKEEPER_WAIT_INTERVAL_SECONDS=1 \
    bash "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh"
}

# Verifies RegionServer member leave decommissions the server, unloads regions, validates emptiness,
# and recommissions on failure.
# Parameters: none.
# Returns: 0 when the planned leave sequence is correct and failures restore assignment eligibility.
verify_regionserver_member_leave() {
  local case_dir="${TMP_DIR}/regionserver-member-leave"
  local command_log="${case_dir}/command.log"
  mkdir -p "${case_dir}/hbase/bin"
  cat >"${case_dir}/hbase/bin/hbase" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "org.apache.hadoop.hbase.util.RegionMover" ]]; then
  printf 'RegionMover:%s\n' "${MOCK_REGIONMOVER_RESULT:-success}" >>"${MOCK_COMMAND_LOG}"
  printf 'RegionMoverArgs:%s\n' "${*:2}" >>"${MOCK_COMMAND_LOG}"
  [[ "${MOCK_REGIONMOVER_RESULT:-success}" == "success" ]]
  exit
fi
if [[ "${1:-}" == "shell" && "${2:-}" == "-n" ]]; then
  input="$(cat)"
  printf '%s\n---\n' "${input}" >>"${MOCK_COMMAND_LOG}"
  if grep -Fq "getLiveServerMetrics" <<<"${input}"; then
    printf 'KB_SERVER_NAME=%s\n' "${MOCK_LIVE_SERVER_NAME:-rs.example,16020,12345}"
    exit 0
  fi
  if grep -Fq "decommissionRegionServers" <<<"${input}"; then
    [[ "${MOCK_DECOMMISSION_RESULT:-success}" == "success" ]] || exit 1
    exit 0
  fi
  if grep -Fq "admin.getRegions(server).size" <<<"${input}"; then
    printf 'KB_REGION_COUNT=%s\n' "${MOCK_REGION_COUNT:-0}"
    exit 0
  fi
  if grep -Fq "recommissionRegionServer" <<<"${input}"; then
    [[ "${MOCK_RECOMMISSION_RESULT:-success}" == "success" ]] || exit 1
    exit 0
  fi
fi
exit 1
EOF
  chmod +x "${case_dir}/hbase/bin/hbase"

  HBASE_HOME="${case_dir}/hbase" \
    KB_LEAVE_MEMBER_POD_FQDN="rs.example" \
    HBASE_REGIONSERVER_PORT="16020" \
    MOCK_COMMAND_LOG="${command_log}" \
    bash "${ROOT_DIR}/addons/hbase/scripts/hregionserver-member-leave.sh"

  grep -Fq "decommissionRegionServers" "${command_log}" || {
    echo "expected RegionServer member leave to decommission the leaving server" >&2
    return 1
  }
  grep -Fq "RegionMover:success" "${command_log}" || {
    echo "expected RegionServer member leave to run RegionMover unload" >&2
    return 1
  }
  grep -Fq "RegionMoverArgs:-m 6 -t 300 -r rs.example -o unload" "${command_log}" || {
    echo "expected RegionServer member leave to run RegionMover with an explicit internal timeout" >&2
    return 1
  }
  grep -Fq "admin.getRegions(server).size" "${command_log}" || {
    echo "expected RegionServer member leave to verify the leaving server is empty" >&2
    return 1
  }
  grep -Fq "recommissionRegionServer" "${command_log}" && {
    echo "expected successful RegionServer member leave to skip recommission" >&2
    return 1
  }

  : >"${command_log}"
  if HBASE_HOME="${case_dir}/hbase" \
    KB_LEAVE_MEMBER_POD_FQDN="rs.example" \
    HBASE_REGIONSERVER_PORT="16020" \
    MOCK_COMMAND_LOG="${command_log}" \
    MOCK_REGION_COUNT="1" \
    bash "${ROOT_DIR}/addons/hbase/scripts/hregionserver-member-leave.sh"; then
    echo "expected RegionServer member leave to fail when the source server remains non-empty" >&2
    return 1
  fi

  grep -Fq "recommissionRegionServer" "${command_log}" || {
    echo "expected RegionServer member leave to recommission the server after non-empty validation failure" >&2
    return 1
  }

  : >"${command_log}"
  if HBASE_HOME="${case_dir}/hbase" \
    KB_LEAVE_MEMBER_POD_FQDN="rs.example" \
    HBASE_REGIONSERVER_PORT="16020" \
    MOCK_COMMAND_LOG="${command_log}" \
    MOCK_REGIONMOVER_RESULT="fail" \
    bash "${ROOT_DIR}/addons/hbase/scripts/hregionserver-member-leave.sh"; then
    echo "expected RegionServer member leave to propagate RegionMover failure" >&2
    return 1
  fi

  grep -Fq "recommissionRegionServer" "${command_log}" || {
    echo "expected RegionServer member leave to recommission the server after RegionMover failure" >&2
    return 1
  }
}

cd "${ROOT_DIR}"

prepare_chart addons/hadoop
prepare_chart addons/hbase
prepare_chart addons-cluster/hadoop
prepare_chart addons-cluster/hbase

verify_hadoop_decommission_host_match
verify_journalnode_probe
verify_regionserver_readiness_marker
verify_hbase_zookeeper_tcp_gate
verify_regionserver_member_leave

helm template test addons/hadoop > "${TMP_DIR}/hadoop-addon.yaml"
helm template test addons/hbase > "${TMP_DIR}/hbase-addon.yaml"
helm template test addons-cluster/hadoop > "${TMP_DIR}/hadoop-cluster.yaml"
helm template test addons-cluster/hbase > "${TMP_DIR}/hbase-cluster-default.yaml"
helm template test addons-cluster/hadoop \
  --set decommission.stateConfigMapName=custom-decommission-state \
  > "${TMP_DIR}/hadoop-cluster-custom-state.yaml"

helm template test addons-cluster/hbase \
  --set-string 'hdfs.namenodeNodes=nn0\,nn1' \
  --set-string 'hdfs.namenodePodFQDNs=nn0.example.com\,nn1.example.com' \
  --set hdfs.nameservice=external-ns \
  --set serviceRefs.hdfsNamenode.enabled=false \
  --set serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster=external-zk-cluster \
  --set serviceRefs.hdfsNamenode.clusterServiceSelector.cluster=external-hdfs-cluster \
  --set hdfs.namenodeRpcPort=9000 \
  --set hdfs.namenodeHttpPort=9871 \
  > "${TMP_DIR}/hbase-cluster-fallback.yaml"

helm template test addons-cluster/hbase \
  --set topology=cluster \
  --set-string 'hdfs.namenodeNodes=nn0\,nn1' \
  --set hdfs.nameservice=external-ns \
  --set serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster=external-zk-cluster \
  --set serviceRefs.hdfsNamenode.enabled=true \
  --set serviceRefs.hdfsNamenode.clusterServiceSelector.cluster=external-hdfs-cluster \
  > "${TMP_DIR}/hbase-cluster-serviceref.yaml"

helm template test addons-cluster/hbase \
  --set topology=cluster \
  --set-string 'hdfs.namenodeNodes=nn0\,nn1' \
  --set hdfs.nameservice=external-ns \
  --set serviceRefs.hbaseZookeeper.clusterServiceSelector.cluster=external-zk-cluster \
  --set serviceRefs.hdfsNamenode.enabled=true \
  --set serviceRefs.hdfsNamenode.clusterServiceSelector.cluster=external-hdfs-cluster \
  > "${TMP_DIR}/hbase-cluster-serviceref-default-ns.yaml"

helm template test addons-cluster/hbase \
  --set topology=standalone \
  > "${TMP_DIR}/hbase-cluster-standalone.yaml"

assert_contains "${TMP_DIR}/hadoop-addon.yaml" "kind: ParamConfigRenderer"
assert_contains "${TMP_DIR}/hadoop-addon.yaml" "name: hdfs-namenode-config-renderer"
assert_contains "${TMP_DIR}/hadoop-addon.yaml" "refresh-decommission-state.sh: |-"
assert_contains "${TMP_DIR}/hadoop-addon.yaml" "datanode-decommission.sh: |-"
assert_contains "${TMP_DIR}/hadoop-addon.yaml" 'name: HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" 'value: "/hadoop/conf/dfs.exclude.dynamic"'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" 'name: HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME_DEFAULT'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" 'value: ""'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" 'name: HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" '{{ if index . "HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME_DEFAULT" }}{{ .HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME_DEFAULT'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" '{{ else }}{{ .CLUSTER_NAME }}-hdfs-decommission-state{{ end }}'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" 'policyRules:'
assert_contains "${TMP_DIR}/hadoop-addon.yaml" '      - configmaps'
assert_contains "${TMP_DIR}/hadoop-cluster.yaml" 'name: test-hdfs-decommission-state'
assert_contains "${TMP_DIR}/hadoop-cluster.yaml" 'name: test-hdfs-decommission-state-editor'
assert_contains "${TMP_DIR}/hadoop-cluster-custom-state.yaml" 'name: custom-decommission-state'
assert_contains "${TMP_DIR}/hadoop-cluster-custom-state.yaml" 'name: custom-decommission-state-editor'
assert_contains "${TMP_DIR}/hadoop-cluster.yaml" 'HDFS_NAMENODE_RESOURCE_DU_RESERVED: "1073741824"'
assert_contains "${TMP_DIR}/hadoop-cluster.yaml" 'HDFS_DATANODE_DU_RESERVED: "1073741824"'
assert_not_contains "${TMP_DIR}/hadoop-cluster.yaml" 'HDFS_NAMENODE_RESOURCE_DU_RESERVED: "1.073741824e+09"'
assert_not_contains "${TMP_DIR}/hadoop-cluster.yaml" 'HDFS_DATANODE_DU_RESERVED: "1.073741824e+09"'
assert_contains "${TMP_DIR}/hadoop-cluster.yaml" 'HDFS_HA_ZOOKEEPER_PARENT_ZNODE_PREFIX: "/hadoop-ha"'
assert_contains "${TMP_DIR}/hadoop-cluster.yaml" 'HDFS_HA_ZOOKEEPER_PARENT_ZNODE_INCLUDE_CLUSTER_UID: "true"'

assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hmaster-live.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hmaster-ready.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hregionserver-live.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hregionserver-ready.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "hregionserver-member-leave.sh: |-"

assert_contains "${TMP_DIR}/hbase-cluster-default.yaml" "topology: cluster"
assert_contains "${TMP_DIR}/hbase-cluster-default.yaml" 'HDFS_NAMESERVICE: "hdfs"'
assert_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" "topology: cluster"
assert_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" 'HDFS_NAMESERVICE: "external-ns"'
assert_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" 'HDFS_NAMENODE_NODES: "nn0,nn1"'
assert_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" 'HDFS_NAMENODE_POD_FQDNS_DEFAULT: "nn0.example.com,nn1.example.com"'
assert_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" 'HDFS_NAMENODE_RPC_PORT: "9000"'
assert_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" 'HDFS_NAMENODE_HTTP_PORT: "9871"'
assert_not_contains "${TMP_DIR}/hbase-cluster-fallback.yaml" "name: hdfs-namenode"
assert_contains "${TMP_DIR}/hbase-cluster-serviceref.yaml" "name: hdfs-namenode"
assert_contains "${TMP_DIR}/hbase-cluster-serviceref-default-ns.yaml" 'HDFS_NAMESERVICE: "external-ns"'
assert_contains "${TMP_DIR}/hbase-cluster-standalone.yaml" 'HBASE_HREGION_MAX_FILESIZE: "10737418240"'
assert_contains "${TMP_DIR}/hbase-cluster-standalone.yaml" 'HBASE_HREGION_MEMSTORE_FLUSH_SIZE: "134217728"'
assert_not_contains "${TMP_DIR}/hbase-cluster-standalone.yaml" 'HBASE_HREGION_MAX_FILESIZE: "1.073741824e+10"'
assert_not_contains "${TMP_DIR}/hbase-cluster-standalone.yaml" 'HBASE_HREGION_MEMSTORE_FLUSH_SIZE: "1.34217728e+08"'

assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-name-status.sh" '_NN_HTTP_PORT="${HDFS_NAMENODE_HTTP_PORT:-9870}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh" '_PORTS="${HDFS_JOURNALNODE_HTTP_PORT:-8480}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-data-status.sh" '_PORTS="${HDFS_DATANODE_HTTP_PORT:-9864}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh" 'curl -fsS --max-time 2'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-data-status.sh" 'curl -fsS --max-time 2'
assert_not_contains "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh" 'grep ClusterId) || true'
assert_not_contains "${ROOT_DIR}/addons/hadoop/scripts/check-data-status.sh" 'grep ClusterId) || true'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'fileName: core-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'fileName: core-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'fileName: hdfs-site.xml'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'fileFormatConfig:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'fileFormatConfig:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'fileFormatConfig:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'fileFormatConfig:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'fileFormatConfig:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'fileFormatConfig:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'componentDef:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'templateName:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'fileFormatConfig:'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-namenode.yaml" 'componentDef: hdfs-namenode'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-namenode-standalone.yaml" 'componentDef: hdfs-namenode-standalone'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-datanode.yaml" 'componentDef: hdfs-datanode'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-datanode-standalone.yaml" 'componentDef: hdfs-datanode-standalone'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-journalnode.yaml" 'componentDef: hdfs-journalnode'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_DATA_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_HTTP_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_IPC_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" 'NAMENODE_POD_FQDN_LIST'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_DATA_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_HTTP_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_IPC_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-namenode.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-namenode.tpl" 'NAMENODE_POD_FQDN_LIST'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-namenode-standalone.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hadoop-env.sh.tpl" '-Ddfs.datanode.hostname=${POD_FQDN:-$(hostname -f 2>/dev/null || hostname)}'
assert_contains "${ROOT_DIR}/addons/hadoop/config/core-site.tpl" 'HDFS_HA_ZOOKEEPER_PARENT_ZNODE_PREFIX'
assert_contains "${ROOT_DIR}/addons/hadoop/config/core-site.tpl" 'CLUSTER_UID'
assert_not_contains "${ROOT_DIR}/addons/hadoop/scripts/init-namenode-format.sh" '|| true'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/init-namenode-format.sh" 'bootstrapStandby'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/start-namenode.sh" 'refresh-decommission-state.sh'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/start-datanode.sh" 'start_unregister_retry_loop'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/start-datanode.sh" 'initial unregister failed, retrying in background'
assert_not_contains "${ROOT_DIR}/addons/hadoop/scripts/start-datanode.sh" 'datanode-decommission.sh" unregister || true'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" 'KB_LEAVE_MEMBER_POD_FQDN'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" 'ensure_state_configmap'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" 'DataNode decommission is disabled, skipping register flow'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/refresh-decommission-state.sh" 'HDFS_DECOMMISSION_REFRESH_PENDING_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/refresh-decommission-state.sh" 'ensure_state_configmap'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/refresh-decommission-state.sh" 'touch "${HDFS_DECOMMISSION_REFRESH_PENDING_FILE}"'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'memberLeave:'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode-standalone.yaml" 'memberLeave:'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'timeoutSeconds: -1'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'externalManaged: true'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode-standalone.yaml" 'externalManaged: true'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'externalManaged: true'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'externalManaged: true'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-journalnode.yaml" 'externalManaged: true'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'minReplicas: 2'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'maxReplicas: 2'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'minReplicas: 1'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'maxReplicas: 1'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-journalnode.yaml" 'minReplicas: 3'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'serviceVersion: "^.*$"'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'preStop:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode-standalone.yaml" 'preStop:'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'name: lifecycle'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'mountPath: /lifecycle'
assert_contains "${ROOT_DIR}/addons-cluster/hadoop/templates/decommission-state-configmap.yaml" 'stateConfigMapName'
assert_contains "${ROOT_DIR}/addons-cluster/hadoop/templates/decommission-rbac.yaml" 'stateConfigMapName'
assert_contains "${ROOT_DIR}/addons-cluster/hadoop/templates/decommission-rbac.yaml" '      - create'
assert_not_contains "${ROOT_DIR}/addons/hbase/scripts/init-hdfs-root-layout.sh" 'mkdir -p "${p}" || true'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_MASTER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_MASTER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_REGIONSERVER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_REGIONSERVER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<name>hbase.io.compress.lz4.codec</name>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec</value>'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hmaster.sh" 'Waiting for ZooKeeper readiness before starting HMaster...'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh" 'Waiting for ZooKeeper readiness before starting RegionServer...'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hmaster.sh" 'exec 3<>/dev/tcp/${host}/${port}'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh" 'exec 3<>/dev/tcp/${host}/${port}'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hmaster.sh" 'ZooKeeper is reachable via ${host}:${port}'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh" 'ZooKeeper is reachable via ${host}:${port}'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hmaster.sh" 'ZOOKEEPER_ENDPOINTS'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh" 'ZOOKEEPER_ENDPOINTS'
bash -n "${ROOT_DIR}/addons/hbase/scripts/start-hmaster.sh"
bash -n "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh"
assert_contains "${ROOT_DIR}/addons/hbase/scripts/check-hregionserver-ready.sh" "status 'simple'"
assert_contains "${ROOT_DIR}/addons/hbase/scripts/check-hregionserver-ready.sh" 'REGIONSERVER_HOST'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/check-hregionserver-ready.sh" 'report-for-duty.ready'
assert_contains "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh" 'rm -f "${HBASE_PID_DIR}/report-for-duty.ready"'
assert_not_contains "${ROOT_DIR}/addons/hbase/scripts/start-hregionserver.sh" 'RegionMover'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'hregionserver-member-leave.sh'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_POD_FQDNS_DEFAULT'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_POD_FQDNS'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'podFQDNs: Optional'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'podFQDNs: Optional'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" "fieldPath: metadata.annotations['kubeblocks.io/pod-fqdn']"
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" "fieldPath: metadata.annotations['kubeblocks.io/pod-fqdn']"
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-env.sh.tpl" '-Dhbase.regionserver.hostname=${POD_FQDN:-$(hostname -f 2>/dev/null || hostname)}'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'optional: true'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'podFQDNs: Optional'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_POD_FQDNS_DEFAULT'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_POD_FQDNS'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'optional: true'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'podFQDNs: Optional'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'serviceVersion: "^.*$"'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hbase-standalone.yaml" 'serviceVersion: "^.*$"'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'port: Required'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'port: Required'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hbase-standalone.yaml" 'port: Required'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'apiVersion: v1'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode-standalone.yaml" 'apiVersion: v1'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'apiVersion: v1'
assert_not_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_HOSTS'
assert_not_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_RPC_ENDPOINTS'
assert_not_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_HOSTS'
assert_not_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_RPC_ENDPOINTS'
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '{{- $podFQDNsRaw := default .HDFS_NAMENODE_POD_FQDNS_DEFAULT .HDFS_NAMENODE_POD_FQDNS }}'
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" 'serviceRefVarRef.podFQDNs or hdfs.namenodePodFQDNs must be provided'
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '<value>{{ trim (index $podFQDNs $i) }}:{{ $rpcPort }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '<value>{{ trim (index $podFQDNs $i) }}:{{ $httpPort }}</value>'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" 'HDFS_NAMENODE_RPC_ENDPOINTS'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" 'HDFS_NAMENODE_HOSTS'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_MASTER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_MASTER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_REGIONSERVER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_REGIONSERVER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<name>hbase.io.compress.lz4.codec</name>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec</value>'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" 'hbase.ipc.server.callqueue.type'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" 'hbase.unsafe.stream.capability.enforce'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" 'hbase.master.logcleaner.plugins'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" 'hbase.master.hfilecleaner.plugins'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" 'hbase.master.procedure.tlogcleaner.plugins'
assert_not_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" 'hbase.unsafe.stream.capability.enforce'
assert_contains "${ROOT_DIR}/addons/hbase/templates/hbase-cluster-config-template.yaml" 'log4j2.properties'
assert_contains "${ROOT_DIR}/addons/hbase/templates/hbase-standalone-config-template.yaml" 'log4j2.properties'
assert_contains "${ROOT_DIR}/addons/hbase/config/log4j2.properties" 'RollingRandomAccessFile'
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-common-site.tpl" 'org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec'

echo "render verification passed"
