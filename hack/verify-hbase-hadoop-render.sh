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

cd "${ROOT_DIR}"

helm dependency build addons-cluster/hbase >/dev/null

helm template test addons-cluster/hbase \
  --set-string 'hdfs.namenodeNodes=nn0\,nn1' \
  --set hdfs.nameservice=external-ns \
  --set serviceRefs.hdfsNamenode.clusterServiceSelector.cluster=external-hdfs-cluster \
  --set hdfs.namenodeRpcPort=9000 \
  --set hdfs.namenodeHttpPort=9871 \
  > "${TMP_DIR}/hbase-cluster.yaml"

assert_contains "${TMP_DIR}/hbase-cluster.yaml" "topology: cluster"
assert_contains "${TMP_DIR}/hbase-cluster.yaml" "port: fs"
assert_contains "${TMP_DIR}/hbase-cluster.yaml" 'HDFS_NAMESERVICE: "external-ns"'
assert_contains "${TMP_DIR}/hbase-cluster.yaml" 'HDFS_NAMENODE_NODES: "nn0,nn1"'
assert_contains "${TMP_DIR}/hbase-cluster.yaml" 'HDFS_NAMENODE_RPC_PORT: "9000"'
assert_contains "${TMP_DIR}/hbase-cluster.yaml" 'HDFS_NAMENODE_HTTP_PORT: "9871"'

assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-name-status.sh" '_NN_HTTP_PORT="${HDFS_NAMENODE_HTTP_PORT:-9870}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-journal-status.sh" '_PORTS="${HDFS_JOURNALNODE_HTTP_PORT:-8480}"'
assert_contains "${ROOT_DIR}/addons/hadoop/scripts/check-data-status.sh" '_PORTS="${HDFS_DATANODE_HTTP_PORT:-9864}"'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'componentDef: ^hdfs-(namenode|datanode|journalnode)$'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'templateName: hdfs-common-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'fileName: core-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common.yaml" 'format: xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'componentDef: ^hdfs-(namenode|datanode)-standalone$'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'templateName: hdfs-common-standalone-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'fileName: core-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-common-standalone.yaml" 'format: xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'componentDef: hdfs-namenode'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'templateName: namenode-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode.yaml" 'format: xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'componentDef: hdfs-namenode-standalone'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'templateName: namenode-standalone-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-namenode-standalone.yaml" 'format: xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'componentDef: hdfs-datanode'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'templateName: datanode-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode.yaml" 'format: xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'componentDef: hdfs-datanode-standalone'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'templateName: datanode-standalone-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-datanode-standalone.yaml" 'format: xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'componentDef: hdfs-journalnode'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'templateName: journalnode-config-template'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'fileName: hdfs-site.xml'
assert_contains "${ROOT_DIR}/addons/hadoop/templates/paramsdef-hdfs-journalnode.yaml" 'format: xml'
assert_not_exists "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-namenode.yaml"
assert_not_exists "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-namenode-standalone.yaml"
assert_not_exists "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-datanode.yaml"
assert_not_exists "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-datanode-standalone.yaml"
assert_not_exists "${ROOT_DIR}/addons/hadoop/templates/pcr-hdfs-journalnode.yaml"
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_DATA_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_HTTP_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_IPC_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_DATA_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_HTTP_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hadoop/config/hdfs-datanode-standalone.tpl" '<value>0.0.0.0:{{- .HDFS_DATANODE_IPC_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_MASTER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_MASTER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_REGIONSERVER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>{{ .HBASE_REGIONSERVER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<name>hbase.io.compress.lz4.codec</name>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-cluster.tpl" '<value>org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec</value>'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_HOSTS'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: HDFS_NAMENODE_RPC_ENDPOINTS'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'name: hdfs-namenode'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'host: Required'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hmaster.yaml" 'endpoint: Required'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_HOSTS'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: HDFS_NAMENODE_RPC_ENDPOINTS'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'name: hdfs-namenode'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'host: Required'
  assert_contains "${ROOT_DIR}/addons/hbase/templates/cmpd-hregionserver.yaml" 'endpoint: Required'
  assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '{{- $rpcEndpoints := splitList "," .HDFS_NAMENODE_RPC_ENDPOINTS }}'
  assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '{{- $hosts := splitList "," .HDFS_NAMENODE_HOSTS }}'
  assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '<value>{{ trim (index $rpcEndpoints $i) }}</value>'
  assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '<value>{{ trim (index $hosts $i) }}:{{ $httpPort }}</value>'
  assert_not_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" 'headlessSvc := printf "%s-namenode-headless" $ns'
  assert_not_contains "${ROOT_DIR}/addons/hbase/config/hdfs-client-site.tpl" '{{ $ns }}-namenode-{{ $ordinal }}.'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_MASTER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_MASTER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_REGIONSERVER_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>{{ .HBASE_REGIONSERVER_INFO_PORT }}</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<name>hbase.io.compress.lz4.codec</name>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hbase-site-standalone.tpl" '<value>org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec</value>'
assert_contains "${ROOT_DIR}/addons/hbase/config/hdfs-common-site.tpl" 'org.apache.hadoop.hbase.io.compress.lz4.Lz4Codec'

echo "render verification passed"
