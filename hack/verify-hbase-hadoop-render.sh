#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "missing expected content: $needle" >&2
    return 1
  fi
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq "$needle" "$file"; then
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

cd "${ROOT_DIR}"

prepare_chart addons/hadoop
prepare_chart addons/hbase
prepare_chart addons-cluster/hadoop
prepare_chart addons-cluster/hbase

verify_hadoop_decommission_host_match

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

assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hmaster-live.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hmaster-ready.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hregionserver-live.sh: |-"
assert_contains "${TMP_DIR}/hbase-addon.yaml" "check-hregionserver-ready.sh: |-"

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

assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-name-status.sh" '_NN_HTTP_PORT="${HDFS_NAMENODE_HTTP_PORT:-9870}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh" '_PORTS="${HDFS_JOURNALNODE_HTTP_PORT:-8480}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-data-status.sh" '_PORTS="${HDFS_DATANODE_HTTP_PORT:-9864}"'
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
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_DATA_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_HTTP_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_IPC_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-namenode.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-namenode-standalone.tpl" '<value>{{- .HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE }}</value>'
assert_not_contains "${ROOT_DIR}/addons/hadoop/scripts/init-namenode-format.sh" '|| true'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/start-namenode.sh" 'refresh-decommission-state.sh'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/start-datanode.sh" 'datanode-decommission.sh" unregister || true'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" 'KB_LEAVE_MEMBER_POD_FQDN'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" 'ensure_state_configmap'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/datanode-decommission.sh" 'DataNode decommission is disabled, skipping register flow'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/refresh-decommission-state.sh" 'HDFS_DECOMMISSION_REFRESH_PENDING_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/refresh-decommission-state.sh" 'ensure_state_configmap'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/refresh-decommission-state.sh" 'touch "${HDFS_DECOMMISSION_REFRESH_PENDING_FILE}"'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'memberLeave:'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode-standalone.yaml" 'memberLeave:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'preStop:'
assert_not_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode-standalone.yaml" 'preStop:'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-datanode.yaml" 'HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode.yaml" 'HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/cmpd-hdfs-namenode-standalone.yaml" 'HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE'
assert_contains "${ROOT_DIR}/addons-cluster/hadoop/templates/decommission-state-configmap.yaml" 'stateConfigMapName'
assert_contains "${ROOT_DIR}/addons-cluster/hadoop/templates/decommission-rbac.yaml" 'stateConfigMapName'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_MASTER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_MASTER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_REGIONSERVER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_REGIONSERVER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<name>hbase.io.compress.lz4.codec</name>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec</value>'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_POD_FQDNS_DEFAULT'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_POD_FQDNS'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'optional: true'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'podFQDNs: Required'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_POD_FQDNS_DEFAULT'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_POD_FQDNS'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'optional: true'
assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'podFQDNs: Required'
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
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-common-site.tpl" 'org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec'

echo "render verification passed"
